#!/usr/bin/env bash
#
# Copyright (c) 2026 byte5 GmbH
# SPDX-License-Identifier: MIT
#
# Build all distribution artifacts from the single Swift source.
#
# Outputs:
#   dist/reminders-eventkit         — compiled binary (matches host arch)
#   dist/apple-reminders.mcpb       — ready-to-install Claude Desktop extension
#   dist/skill/                     — standalone Claude Code skill directory
#
# Signing: set SIGNING_IDENTITY to a Developer ID to sign the binary with
# Hardened Runtime. The release workflow sets this automatically; local
# builds are unsigned unless you opt in.
#
# Usage:
#   ./build.sh              # build everything (binary + skill + mcpb)
#   ./build.sh binary       # just the Swift binary
#   ./build.sh skill        # just the Claude Code skill directory
#   ./build.sh mcpb         # just the .mcpb bundle
#   ./build.sh clean        # wipe dist/

set -euo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"
DIST="$REPO/dist"
BINARY_SRC="$REPO/src/reminders-eventkit.swift"
BINARY_OUT="$DIST/reminders-eventkit"
ENTITLEMENTS="$REPO/src/entitlements.plist"

build_binary() {
  echo "[build] compiling Swift binary → $BINARY_OUT"
  mkdir -p "$DIST"
  /usr/bin/swiftc -O "$BINARY_SRC" -o "$BINARY_OUT"
  chmod +x "$BINARY_OUT"

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
  (cd "$STAGE" && npm ci --silent --omit=dev)
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
  all)    build_binary && build_skill && build_mcpb ;;
  *)      echo "Usage: $0 [binary|skill|mcpb|clean|all]" >&2; exit 1 ;;
esac
