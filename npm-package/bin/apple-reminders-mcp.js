#!/usr/bin/env node
// Entry shim for the npm-distributed Apple Reminders MCP server.
// Resolves the bundled Swift binary path, then delegates to ../server/index.js.

import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";
import { existsSync } from "node:fs";

const here = dirname(fileURLToPath(import.meta.url));
const bundledBinary = resolve(here, "..", "bin", "reminders-eventkit");

if (!process.env.REMINDERS_BINARY) {
  if (!existsSync(bundledBinary)) {
    console.error(
      `apple-reminders-mcp: bundled binary not found at ${bundledBinary}.\n` +
        `The postinstall step should have downloaded it — try 'npm rebuild @high5ventures/apple-reminders-mcp' or reinstall.`
    );
    process.exit(1);
  }
  process.env.REMINDERS_BINARY = bundledBinary;
}

await import(resolve(here, "..", "server", "index.js"));
