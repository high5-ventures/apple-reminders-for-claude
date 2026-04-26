#!/usr/bin/env bash
# Notarize a file (.mcpb bundle or standalone binary zip) with Apple's notary
# service, then staple the result so it works offline on end-user Macs.
#
# Required env vars:
#   APPLE_ID                      — Apple ID email tied to the developer account
#   APPLE_APP_SPECIFIC_PASSWORD   — app-specific password from appleid.apple.com
#   APPLE_TEAM_ID                 — 10-char Team ID (e.g. "AB12CD34EF")
#
# Usage:
#   ./scripts/notarize.sh <path-to-file>
#
# Notes:
#   - notarytool requires a zip/pkg/dmg; for single binaries, zip first.
#   - stapler staple works on .pkg/.dmg/.app/.mcpb but NOT on bare binaries —
#     a standalone binary cannot be stapled, only soft-verified online.
#     (That's why we primarily notarize the .mcpb, which is a zip.)

set -euo pipefail

TARGET="${1:-}"
if [[ -z "$TARGET" ]]; then
  echo "Usage: $0 <file-to-notarize>" >&2
  exit 2
fi
if [[ ! -f "$TARGET" ]]; then
  echo "notarize: file not found: $TARGET" >&2
  exit 2
fi

: "${APPLE_ID:?APPLE_ID is required}"
: "${APPLE_APP_SPECIFIC_PASSWORD:?APPLE_APP_SPECIFIC_PASSWORD is required}"
: "${APPLE_TEAM_ID:?APPLE_TEAM_ID is required}"

echo "[notarize] submitting $TARGET to Apple notary service…"
SUBMISSION_OUTPUT=$(xcrun notarytool submit "$TARGET" \
  --apple-id "$APPLE_ID" \
  --password "$APPLE_APP_SPECIFIC_PASSWORD" \
  --team-id "$APPLE_TEAM_ID" \
  --wait \
  --output-format json)

echo "$SUBMISSION_OUTPUT"

STATUS=$(echo "$SUBMISSION_OUTPUT" | sed -n 's/.*"status": *"\([^"]*\)".*/\1/p' | head -1)
SUBMISSION_ID=$(echo "$SUBMISSION_OUTPUT" | sed -n 's/.*"id": *"\([^"]*\)".*/\1/p' | head -1)

if [[ "$STATUS" != "Accepted" ]]; then
  echo "[notarize] submission NOT accepted (status: $STATUS). Fetching log…" >&2
  if [[ -n "$SUBMISSION_ID" ]]; then
    xcrun notarytool log "$SUBMISSION_ID" \
      --apple-id "$APPLE_ID" \
      --password "$APPLE_APP_SPECIFIC_PASSWORD" \
      --team-id "$APPLE_TEAM_ID" >&2 || true
  fi
  exit 1
fi

case "$TARGET" in
  *.mcpb|*.pkg|*.dmg|*.app)
    echo "[notarize] stapling ticket to $TARGET"
    xcrun stapler staple "$TARGET"
    xcrun stapler validate "$TARGET"
    ;;
  *)
    echo "[notarize] $TARGET is not staplable; notarization is online-only." >&2
    ;;
esac

echo "[notarize] done."
