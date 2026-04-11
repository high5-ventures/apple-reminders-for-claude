#!/usr/bin/env bash
#
# Copyright (c) 2026 byte5 GmbH
# SPDX-License-Identifier: MIT
#
# Build both distribution artifacts from the single Swift source.
#
# Outputs:
#   dist/reminders-eventkit         — compiled binary (arm64 or x86_64, matching host)
#   dist/apple-reminders.mcpb       — ready-to-install Claude Desktop extension
#   dist/skill/                     — ready-to-copy Claude Code skill directory
#
# Usage:
#   ./build.sh              # build everything
#   ./build.sh binary       # just the Swift binary
#   ./build.sh skill        # just the Claude Code skill directory
#   ./build.sh mcpb         # just the .mcpb bundle
#   ./build.sh clean        # wipe dist/

set -euo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"
DIST="$REPO/dist"
BINARY_SRC="$REPO/src/reminders-eventkit.swift"
BINARY_OUT="$DIST/reminders-eventkit"

build_binary() {
  echo "[build] compiling Swift binary → $BINARY_OUT"
  mkdir -p "$DIST"
  /usr/bin/swiftc -O "$BINARY_SRC" -o "$BINARY_OUT"
  chmod +x "$BINARY_OUT"
  file "$BINARY_OUT"
}

build_skill() {
  [[ -x "$BINARY_OUT" ]] || build_binary
  echo "[build] assembling skill directory → $DIST/skill"
  rm -rf "$DIST/skill"
  mkdir -p "$DIST/skill/bin" "$DIST/skill/lib" "$DIST/skill/scripts"
  cp "$REPO/skill/SKILL.md"                       "$DIST/skill/"
  cp "$REPO/skill/lib/_prelude.applescript"       "$DIST/skill/lib/"
  cp "$REPO/skill/scripts/get_flagged.applescript" "$DIST/skill/scripts/"
  cp "$BINARY_OUT"                                "$DIST/skill/bin/"
  echo "[build] skill ready at $DIST/skill"
}

build_mcpb() {
  [[ -x "$BINARY_OUT" ]] || build_binary
  echo "[build] assembling .mcpb bundle"
  local STAGE="$DIST/mcpb-stage"
  rm -rf "$STAGE"
  mkdir -p "$STAGE/server" "$STAGE/bin"
  cp "$REPO/mcpb/manifest.json"      "$STAGE/"
  cp "$REPO/mcpb/package.json"       "$STAGE/"
  cp "$REPO/mcpb/package-lock.json"  "$STAGE/"
  cp "$REPO/mcpb/server/index.js"    "$STAGE/server/"
  cp "$BINARY_OUT"                   "$STAGE/bin/"
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
