#!/usr/bin/env node
// postinstall: download the signed, notarized Swift binary matching this
// package version from GitHub Releases, verify its Developer ID signature,
// and drop it at bin/reminders-eventkit.
//
// Exits non-zero only when running on macOS and the download fails.
// On non-darwin platforms, exits 0 silently (the package is os:darwin gated
// already, but CI runners sometimes run postinstall anyway).

import { createWriteStream, existsSync, mkdirSync, chmodSync, rmSync } from "node:fs";
import { mkdtemp, readFile } from "node:fs/promises";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { pipeline } from "node:stream/promises";
import { spawnSync } from "node:child_process";
import { tmpdir } from "node:os";

if (process.platform !== "darwin") {
  console.warn(
    `@high5ventures/apple-reminders-mcp only runs on macOS (got ${process.platform}) — skipping binary download.`
  );
  process.exit(0);
}

const here = dirname(fileURLToPath(import.meta.url));
const pkg = JSON.parse(
  await readFile(resolve(here, "..", "package.json"), "utf8")
);
const version = pkg.version;

const binDir = resolve(here, "..", "bin");
const target = resolve(binDir, "reminders-eventkit");
const url = `https://github.com/high5-ventures/apple-reminders-for-claude/releases/download/v${version}/reminders-eventkit`;
const expectedAuthority = /Authority=Developer ID Application: high5 ventures GmbH/;

mkdirSync(binDir, { recursive: true });

function verifySignature(path) {
  const verify = spawnSync("codesign", ["--verify", "--verbose", path], {
    encoding: "utf8",
  });
  if (verify.status !== 0) {
    return { ok: false, reason: verify.stderr || verify.stdout };
  }
  const identity = spawnSync("codesign", ["-dv", path], { encoding: "utf8" });
  const combined = (identity.stderr || "") + (identity.stdout || "");
  if (!expectedAuthority.test(combined)) {
    return { ok: false, reason: `unexpected signer:\n${combined}` };
  }
  return { ok: true };
}

// Re-verify the cached binary on every install so a tampered file doesn't
// persist silently across upgrades. If verification fails, fall through to
// re-download.
if (existsSync(target)) {
  const check = verifySignature(target);
  if (check.ok) {
    process.exit(0);
  }
  console.warn(
    `apple-reminders-mcp: cached binary failed re-verification, redownloading. Reason: ${check.reason}`
  );
}

console.log(
  `apple-reminders-mcp: downloading signed v${version} binary from GitHub Releases…`
);

// mkdtemp gives us an unguessable, exclusive-owned directory so a same-user
// attacker cannot pre-create a symlink or clobber the partial download.
const tmpDir = await mkdtemp(join(tmpdir(), "apple-reminders-mcp-"));
const tmp = join(tmpDir, "reminders-eventkit");

async function download(srcUrl, dest, redirects = 0) {
  if (redirects > 5) throw new Error("too many redirects");
  const res = await fetch(srcUrl, { redirect: "manual" });
  if (res.status >= 300 && res.status < 400 && res.headers.get("location")) {
    return download(res.headers.get("location"), dest, redirects + 1);
  }
  if (!res.ok) {
    throw new Error(`HTTP ${res.status} for ${srcUrl}`);
  }
  await pipeline(res.body, createWriteStream(dest));
}

try {
  await download(url, tmp);
  chmodSync(tmp, 0o755);

  const check = verifySignature(tmp);
  if (!check.ok) {
    throw new Error(
      `codesign verification failed: ${check.reason}\nExpected signer: 'Developer ID Application: high5 ventures GmbH'`
    );
  }

  const { renameSync } = await import("node:fs");
  renameSync(tmp, target);
  console.log(`apple-reminders-mcp: installed ${target}`);
} catch (err) {
  console.error(
    `apple-reminders-mcp postinstall failed: ${err.message || err}\n` +
      `You can still build the binary locally from source:\n` +
      `  git clone https://github.com/high5-ventures/apple-reminders-for-claude\n` +
      `  cd apple-reminders-for-claude && ./build.sh binary\n` +
      `  cp dist/reminders-eventkit "${target}"`
  );
  process.exit(1);
} finally {
  // Always clean up the temp dir so we don't leave partial downloads or the
  // staged binary sitting in /tmp under an unguessable but still-existing path.
  rmSync(tmpDir, { recursive: true, force: true });
}
