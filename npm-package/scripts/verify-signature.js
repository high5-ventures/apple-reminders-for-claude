#!/usr/bin/env node
// Copyright (c) 2026 high5 ventures GmbH
// SPDX-License-Identifier: MIT
//
// Verify that a file is an intact Mach-O binary signed by high5 ventures'
// Developer ID. Used by the postinstall (scripts/install-binary.js) and
// runnable directly as a CLI so CI exercises the very code the installer uses.
//
// We evaluate a code-signing *requirement* instead of grepping `codesign -d`
// output. The human-readable dump does not emit `Authority=` lines at
// verbosity 1, so the previous `codesign -dv` + regex check could never match
// and failed every install (issues #2, #3). A requirement is evaluated by
// codesign itself and pins the full chain — Apple anchor, Developer ID CA,
// Developer ID Application leaf, and our team ID.
//
// The leading `=` in `-R=` is load-bearing: without it codesign treats the
// argument as a path to a requirement *file* and the check fails outright.
//
// Keep in sync with scripts/verify-signature.sh — CI exercises both against a
// known-good signed binary and against a foreign signature.

import { spawnSync } from "node:child_process";
import { pathToFileURL } from "node:url";

export const TEAM_ID = "VG5X6JCLGF";

export const REQUIREMENT =
  "anchor apple generic" +
  " and certificate 1[field.1.2.840.113635.100.6.2.6]" +
  " and certificate leaf[field.1.2.840.113635.100.6.1.13]" +
  ` and certificate leaf[subject.OU] = "${TEAM_ID}"`;

export function verifySignature(path) {
  const res = spawnSync(
    "codesign",
    ["--verify", "--verbose", `-R=${REQUIREMENT}`, path],
    { encoding: "utf8" }
  );

  if (res.error) {
    return { ok: false, reason: `could not run codesign: ${res.error.message}` };
  }
  if (res.status !== 0) {
    const dump = spawnSync("codesign", ["-dvvv", path], { encoding: "utf8" });
    const detail = ((dump.stderr || "") + (dump.stdout || "")).trim();
    const why = (res.stderr || res.stdout || "requirement not satisfied").trim();
    return {
      ok: false,
      reason: detail ? `${why}\nactual signature:\n${detail}` : why,
    };
  }
  return { ok: true };
}

// CLI mode: `node verify-signature.js <path>` — exit 0 when signed by us.
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const target = process.argv[2];
  if (!target) {
    console.error("verify-signature: usage: verify-signature.js <path>");
    process.exit(2);
  }
  const result = verifySignature(target);
  if (!result.ok) {
    console.error(
      `verify-signature: ${target} is not signed by 'Developer ID Application: high5 ventures GmbH' (team ${TEAM_ID})\n${result.reason}`
    );
    process.exit(1);
  }
}
