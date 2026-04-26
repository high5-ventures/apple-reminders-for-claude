#!/bin/bash
# SessionStart hook — ensure the signed, notarized reminders-eventkit binary is
# available to the skill before any tool invocation.
#
# Downloads the binary from the matching GitHub release on first use and on
# version bumps, verifies the Apple Developer signature, and symlinks it into
# the skill's bin/ directory so SKILL.md's relative path keeps working.

set -euo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
PLUGIN_DATA="${CLAUDE_PLUGIN_DATA:-$HOME/.claude/plugins/data/apple-reminders-unknown}"
PLUGIN_VERSION_FILE="${PLUGIN_ROOT}/.claude-plugin/plugin.json"

VERSION=$(sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' "$PLUGIN_VERSION_FILE" | head -1)
if [[ -z "$VERSION" ]]; then
    echo "install-binary: could not determine plugin version from $PLUGIN_VERSION_FILE" >&2
    exit 1
fi

BIN_DIR="${PLUGIN_DATA}/bin"
BIN_PATH="${BIN_DIR}/reminders-eventkit"
VERSION_MARKER="${BIN_DIR}/.version"
TARGET_URL="https://github.com/byte5ai/apple-reminders-for-claude/releases/download/v${VERSION}/reminders-eventkit"

SKILL_BIN_DIR="${PLUGIN_ROOT}/skills/apple-reminders/bin"
SKILL_BIN_LINK="${SKILL_BIN_DIR}/reminders-eventkit"

mkdir -p "$BIN_DIR" "$SKILL_BIN_DIR"

# Reuse existing download if version matches
if [[ -x "$BIN_PATH" && -f "$VERSION_MARKER" ]]; then
    if [[ "$(cat "$VERSION_MARKER")" == "$VERSION" ]]; then
        ln -sf "$BIN_PATH" "$SKILL_BIN_LINK"
        exit 0
    fi
fi

echo "Downloading apple-reminders-for-claude v${VERSION} binary…" >&2
TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT

if ! curl --fail --silent --location --output "$TMP" "$TARGET_URL"; then
    echo "install-binary: download failed from $TARGET_URL" >&2
    echo "If you are developing locally, place a built binary at: $SKILL_BIN_LINK" >&2
    exit 1
fi

# Verify Apple Developer signature before trusting the binary
chmod +x "$TMP"
if ! codesign --verify --verbose "$TMP" 2>/dev/null; then
    echo "install-binary: codesign verification failed — refusing to install" >&2
    exit 1
fi

# Verify the signer is byte5 GmbH, not an attacker with a different Developer ID
if ! codesign -dv "$TMP" 2>&1 | grep -q 'Authority=Developer ID Application: byte5 GmbH'; then
    echo "install-binary: signer mismatch — expected 'Developer ID Application: byte5 GmbH'" >&2
    codesign -dv "$TMP" 2>&1 >&2
    exit 1
fi

mv "$TMP" "$BIN_PATH"
trap - EXIT
echo "$VERSION" > "$VERSION_MARKER"
ln -sf "$BIN_PATH" "$SKILL_BIN_LINK"

echo "apple-reminders binary v${VERSION} installed at $BIN_PATH" >&2
