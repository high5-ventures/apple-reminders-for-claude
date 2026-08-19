#!/bin/bash
#
# Copyright (c) 2026 high5 ventures GmbH
# SPDX-License-Identifier: MIT
#
# Verify that a file is an intact Mach-O binary signed by high5 ventures'
# Developer ID. Single source of truth for the signer check performed by the
# SessionStart hook (scripts/install-binary.sh).
#
# We evaluate a code-signing *requirement* instead of grepping `codesign -d`
# output. The human-readable dump does not emit `Authority=` lines at
# verbosity 1, so the previous `codesign -dv … | grep Authority=` check could
# never match and turned every install into a false "signer mismatch"
# (issues #2, #3). A requirement is evaluated by codesign itself and pins the
# full chain — Apple anchor, Developer ID CA, Developer ID Application leaf,
# and our team ID — rather than matching display text at a verbosity level
# that is not part of any contract.
#
# The leading `=` in `-R=` is load-bearing: without it codesign treats the
# argument as a path to a requirement *file* and the check fails outright.
#
# npm-package/scripts/verify-signature.js carries the same requirement for the
# npm install path. Keep both in sync — CI exercises each against a known-good
# signed binary and against a foreign signature.
#
# Usage: verify-signature.sh <path>   → exit 0 when signed by us

set -euo pipefail

TEAM_ID="VG5X6JCLGF"
REQUIREMENT='anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] and certificate leaf[field.1.2.840.113635.100.6.1.13] and certificate leaf[subject.OU] = "VG5X6JCLGF"'

TARGET="${1:-}"
if [[ -z "$TARGET" ]]; then
    echo "verify-signature: usage: $0 <path>" >&2
    exit 2
fi

if codesign --verify --verbose -R="$REQUIREMENT" "$TARGET" 2>/dev/null; then
    exit 0
fi

echo "verify-signature: $TARGET is not signed by 'Developer ID Application: high5 ventures GmbH' (team $TEAM_ID)" >&2
echo "verify-signature: actual signature follows —" >&2
codesign -dvvv "$TARGET" >&2 || true
exit 1
