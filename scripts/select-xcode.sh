#!/bin/bash
#
# Copyright (c) 2026 high5 ventures GmbH
# SPDX-License-Identifier: MIT
#
# Select the Xcode a CI job builds with, by major version, and log the
# toolchain it brings. Exports DEVELOPER_DIR through $GITHUB_ENV, so it must
# run as its own step before the first step that compiles. That needs no
# root, unlike `sudo xcode-select`, and names no fixed path: the Xcode
# installs a runner image carries are only known from inside it.
#
# Usage: select-xcode.sh <major>   e.g. select-xcode.sh 27

set -euo pipefail

MAJOR="${1:-}"
if [[ ! "$MAJOR" =~ ^[0-9]+$ ]]; then
    echo "select-xcode: usage: $0 <major>" >&2
    exit 2
fi

SELECTED=""
for app in /Applications/Xcode*.app; do
    dev="$app/Contents/Developer"
    [[ -d "$dev" ]] || continue
    version=$(DEVELOPER_DIR="$dev" xcodebuild -version 2>/dev/null | head -1 || true)
    echo "select-xcode: $app → ${version:-unreadable}"
    if [[ -z "$SELECTED" && ( "$version" == "Xcode $MAJOR" || "$version" == "Xcode $MAJOR."* ) ]]; then
        SELECTED="$dev"
    fi
done

if [[ -z "$SELECTED" ]]; then
    echo "select-xcode: no Xcode $MAJOR in /Applications" >&2
    exit 1
fi

export DEVELOPER_DIR="$SELECTED"
if [[ -n "${GITHUB_ENV:-}" ]]; then
    echo "DEVELOPER_DIR=$SELECTED" >> "$GITHUB_ENV"
fi

SDK=$(xcrun --sdk macosx --show-sdk-path)
echo "select-xcode: DEVELOPER_DIR=$SELECTED"
xcodebuild -version
swiftc --version 2>&1
echo "macOS SDK $(xcrun --sdk macosx --show-sdk-version), deploys to macOS" \
    "$(plutil -extract SupportedTargets.macosx.MinimumDeploymentTarget raw "$SDK/SDKSettings.plist" 2>/dev/null || echo '?')" \
    "and later"
# The macrunner image records its tool versions here; other runners have none.
if [[ -f /Users/Shared/macrunner-image.txt ]]; then
    cat /Users/Shared/macrunner-image.txt
fi
