#!/usr/bin/env bash
#
# Copyright (c) 2026 high5 ventures GmbH
# SPDX-License-Identifier: MIT
#
# Build all distribution artifacts from the single Swift source.
#
# Outputs:
#   dist/reminders-eventkit         — universal binary (arm64 + x86_64), macOS 11+
#   dist/apple-reminders.mcpb       — ready-to-install Claude Desktop extension
#   dist/skill/                     — standalone Claude Code skill directory
#
# Signing: set SIGNING_IDENTITY to a Developer ID to sign the binary with
# Hardened Runtime. The release workflow sets this automatically; local
# builds are unsigned unless you opt in.
#
# Architectures: set ARCHS to build a subset, e.g. ARCHS=arm64 for a faster
# local build. Releases always use the default, both architectures.
#
# Usage:
#   ./build.sh              # build everything (binary + skill + mcpb)
#   ./build.sh binary       # just the Swift binary
#   ./build.sh skill        # just the Claude Code skill directory
#   ./build.sh mcpb         # just the .mcpb bundle
#   ./build.sh clean        # wipe dist/

set -Eeuo pipefail

# Name the failing command instead of exiting silently: a tool that prints
# nothing on failure otherwise leaves only the last "[build]" line behind.
trap 'echo "[build] failed (exit $?) at line $LINENO: $BASH_COMMAND" >&2' ERR

REPO="$(cd "$(dirname "$0")" && pwd)"
DIST="$REPO/dist"
BINARY_SRC="$REPO/src/reminders-eventkit.swift"
BINARY_OUT="$DIST/reminders-eventkit"
ENTITLEMENTS="$REPO/src/entitlements.plist"
INFO_PLIST="$REPO/src/Info.plist"

# Without an explicit -target, swiftc builds only the host architecture and
# takes the build machine's macOS version as the minimum. That is how v1.0.4
# shipped arm64-only with a macOS 14 minimum, which fails to launch on Intel
# Macs and on Apple Silicon before macOS 14 (#21).
MACOS_MIN="11.0"
ARCHS="${ARCHS:-arm64 x86_64}"

build_binary() {
  echo "[build] compiling Swift binary ($ARCHS, macOS $MACOS_MIN+) → $BINARY_OUT"
  mkdir -p "$DIST"
  local arch slice
  local slices=()
  for arch in $ARCHS; do
    slice="$DIST/reminders-eventkit-$arch"
    # A bare executable has no bundle, so the Info.plist is linked into a
    # __TEXT,__info_plist section. Without it macOS finds no usage description
    # for the process and refuses Reminders access before EventKit is reached.
    /usr/bin/swiftc -O -target "$arch-apple-macos$MACOS_MIN" "$BINARY_SRC" -o "$slice" \
      -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker "$INFO_PLIST"

    if ! grep -q NSRemindersFullAccessUsageDescription "$slice"; then
      echo "[build] embedded Info.plist missing from the $arch slice — refusing to ship" >&2
      exit 1
    fi

    local minos
    minos=$(otool -l "$slice" \
      | awk '$2 == "LC_BUILD_VERSION" {found = 1} found && $1 == "minos" {print $2; exit}')
    if [[ "$minos" != "$MACOS_MIN" ]]; then
      echo "[build] the $arch slice requires macOS '$minos', expected $MACOS_MIN — refusing to ship" >&2
      exit 1
    fi
    slices+=("$slice")
  done

  if [[ ${#slices[@]} -eq 1 ]]; then
    mv "${slices[0]}" "$BINARY_OUT"
  else
    lipo -create "${slices[@]}" -output "$BINARY_OUT"
    rm -f "${slices[@]}"
  fi
  chmod +x "$BINARY_OUT"

  # lipo lists slices in file order, so compare sorted.
  local want have
  want=$(printf '%s\n' $ARCHS | sort | xargs)
  have=$(lipo -archs "$BINARY_OUT" | tr ' ' '\n' | sort | xargs)
  if [[ "$have" != "$want" ]]; then
    echo "[build] $BINARY_OUT contains '$have', expected '$want' — refusing to ship" >&2
    exit 1
  fi

  if [[ -n "${SIGNING_IDENTITY:-}" ]]; then
    echo "[build] signing binary with $SIGNING_IDENTITY"
    codesign --force --options runtime --timestamp \
      ${ENTITLEMENTS:+--entitlements "$ENTITLEMENTS"} \
      --sign "$SIGNING_IDENTITY" \
      "$BINARY_OUT"
    codesign --verify --verbose "$BINARY_OUT"
  else
    echo "[build] SIGNING_IDENTITY not set — producing unsigned dev binary"
  fi

  file "$BINARY_OUT"
}

build_skill() {
  [[ -x "$BINARY_OUT" ]] || build_binary
  echo "[build] assembling standalone skill directory → $DIST/skill"
  rm -rf "$DIST/skill"
  mkdir -p "$DIST/skill/bin" "$DIST/skill/lib" "$DIST/skill/scripts"
  cp "$REPO/skills/apple-reminders/SKILL.md"                        "$DIST/skill/"
  cp "$REPO/skills/apple-reminders/lib/_prelude.applescript"        "$DIST/skill/lib/"
  cp "$REPO/skills/apple-reminders/scripts/get_flagged.applescript" "$DIST/skill/scripts/"
  cp "$BINARY_OUT"                                                  "$DIST/skill/bin/"
  echo "[build] skill ready at $DIST/skill"
  echo "[build] install via: cp -r $DIST/skill ~/.claude/skills/apple-reminders"
}

build_mcpb() {
  [[ -x "$BINARY_OUT" ]] || build_binary
  echo "[build] assembling .mcpb bundle"
  local STAGE="$DIST/mcpb-stage"
  rm -rf "$STAGE"
  mkdir -p "$STAGE/server" "$STAGE/bin"
  # Metadata + dependency set come from mcpb/; the actual server source comes
  # from the canonical npm-package/server to avoid duplication.
  cp "$REPO/mcpb/manifest.json"             "$STAGE/"
  cp "$REPO/mcpb/package.json"              "$STAGE/"
  cp "$REPO/mcpb/package-lock.json"         "$STAGE/"
  cp "$REPO/mcpb/.mcpbignore"               "$STAGE/" 2>/dev/null || true
  cp "$REPO/npm-package/server/index.js"    "$STAGE/server/"
  cp "$BINARY_OUT"                          "$STAGE/bin/reminders-eventkit"
  [[ -f "$REPO/assets/icon.png" ]] && cp "$REPO/assets/icon.png" "$STAGE/"
  # Reproducible install from the committed lockfile — no resolver drift.
  # Not --silent: that also hides npm's own error, such as EACCES on a
  # root-owned ~/.npm cache, and the build then just stops here (#21).
  npm --prefix "$STAGE" ci --omit=dev --no-audit --no-fund
  command -v mcpb >/dev/null 2>&1 || {
    echo "[build] 'mcpb' CLI not found — install with: npm install -g @anthropic-ai/mcpb" >&2
    exit 1
  }
  mcpb pack "$STAGE" "$DIST/apple-reminders.mcpb"
  rm -rf "$STAGE"
  echo "[build] bundle ready at $DIST/apple-reminders.mcpb"
}

clean() {
  echo "[build] removing $DIST"
  rm -rf "$DIST"
}

case "${1:-all}" in
  binary) build_binary ;;
  skill)  build_skill  ;;
  mcpb)   build_mcpb   ;;
  clean)  clean        ;;
  # Sequential, not chained with &&: bash ignores `set -e` (and the ERR trap)
  # inside every function of an && list except the last one.
  all)    build_binary; build_skill; build_mcpb ;;
  *)      echo "Usage: $0 [binary|skill|mcpb|clean|all]" >&2; exit 1 ;;
esac
