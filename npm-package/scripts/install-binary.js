#!/usr/bin/env node
// postinstall: download the signed, notarized Swift binary matching this
// package version from GitHub Releases, verify its Developer ID signature,
// and drop it at bin/reminders-eventkit.
//
// Exits non-zero only when running on macOS and the download fails.
// On non-darwin platforms, exits 0 silently (the package is os:darwin gated
// already, but CI runners sometimes run postinstall anyway).

import { createWriteStream, existsSync, mkdirSync, chmodSync } from "node:fs";
import { readFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { pipeline } from "node:stream/promises";
import { spawnSync } from "node:child_process";
import { tmpdir } from "node:os";

if (process.platform !== "darwin") {
  console.warn(
    `@byte5ai/apple-reminders-mcp only runs on macOS (got ${process.platform}) — skipping binary download.`
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
const url = `https://github.com/byte5ai/apple-reminders-for-claude/releases/download/v${version}/reminders-eventkit`;

mkdirSync(binDir, { recursive: true });

if (existsSync(target)) {
  process.exit(0);
}

console.log(
  `apple-reminders-mcp: downloading signed v${version} binary from GitHub Releases…`
);

const tmp = resolve(tmpdir(), `reminders-eventkit-${version}-${process.pid}`);

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

  const verify = spawnSync("codesign", ["--verify", "--verbose", tmp], {
    encoding: "utf8",
  });
  if (verify.status !== 0) {
    throw new Error(
      `codesign verification failed:\n${verify.stderr || verify.stdout}`
    );
  }

  const identity = spawnSync("codesign", ["-dv", tmp], { encoding: "utf8" });
  const combined = (identity.stderr || "") + (identity.stdout || "");
  if (!/Authority=Developer ID Application: byte5 GmbH/.test(combined)) {
    throw new Error(
      `unexpected signer — expected 'Developer ID Application: byte5 GmbH'\n${combined}`
    );
  }

  await readFile(tmp); // force flush before rename
  const { renameSync } = await import("node:fs");
  renameSync(tmp, target);
  console.log(`apple-reminders-mcp: installed ${target}`);
} catch (err) {
  console.error(
    `apple-reminders-mcp postinstall failed: ${err.message || err}\n` +
      `You can still build the binary locally from source:\n` +
      `  git clone https://github.com/byte5ai/apple-reminders-for-claude\n` +
      `  cd apple-reminders-for-claude && ./build.sh binary\n` +
      `  cp dist/reminders-eventkit "${target}"`
  );
  process.exit(1);
}
