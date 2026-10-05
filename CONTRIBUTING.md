# Contributing

Thanks for your interest in contributing to Apple Reminders for Claude. This document describes how to set up a development environment, the style expectations, and the release process.

## Code of conduct

Be respectful. Assume good faith. No harassment, no discriminatory language. Maintainers reserve the right to remove comments, close issues, and ban repeat offenders.

## Development setup

Requirements:

- macOS 11 (Big Sur) or newer
- Xcode Command Line Tools (`xcode-select --install`) — provides `swiftc`
- Node.js 18 or newer
- `npm` 9 or newer
- `@anthropic-ai/mcpb` CLI (`npm install -g @anthropic-ai/mcpb`)

Clone and build:

```bash
git clone https://github.com/high5-ventures/apple-reminders-for-claude.git
cd apple-reminders-for-claude
./build.sh
```

The unified build produces:

- `dist/reminders-eventkit` — unsigned universal Swift binary (arm64 + x86_64, macOS 11+) for local dev; `ARCHS=arm64 ./build.sh` builds a single architecture
- `dist/skill/` — skill directory for Claude Code (copy to `~/.claude/skills/apple-reminders/`)
- `dist/apple-reminders.mcpb` — unsigned bundle for Claude Desktop

For signed/notarized release artifacts, see [Release process](#release-process) below — those are built by CI from tagged commits only.

## Project structure

```
src/                    Swift source (single file, EventKit wrapper)
npm-package/            npm-published MCP server (single source of truth)
├── server/index.js     Node.js MCP wrapper
├── scripts/install-binary.js  postinstall: download + verify signed binary
├── package.json        npm package metadata
└── server.json         MCP Registry server descriptor
mcpb/                   Claude Desktop / Cowork extension build set
├── manifest.json       MCPB manifest (spec 0.3)
├── package.json        bundled-runtime npm deps (MCP SDK)
└── icon.png
skills/apple-reminders/ Claude Code skill (AppleScript fallback for flagged)
├── SKILL.md            Skill definition + protocol docs
├── lib/                Shared AppleScript helpers
└── scripts/            AppleScript fallback scripts
.claude-plugin/         Claude Code plugin + marketplace manifests
hooks/                  Plugin SessionStart hook (downloads binary)
scripts/                install-binary.sh + notarize.sh
build.sh                Orchestrator — binary / skill / mcpb / clean / all
.github/workflows/      CI + signed release pipeline
```

The Node MCP server source lives only in `npm-package/server/`. The `.mcpb`
build copies it from there at packing time so there is no duplicate to drift.

## Coding standards

**Swift (`src/reminders-eventkit.swift`):**

- Use `Json.ok()` / `Json.err()` / `Json.errWith()` — never emit ad-hoc JSON.
- Validate command name + arity *before* calling `Store.shared.requestAccessOrExit()` so typos never trigger the TCC prompt.
- Read JSON payloads via stdin when the argv slot is `"-"`. Never parse untrusted content from argv.
- Keep the file single-source, no external Swift packages — simplifies notarization.

**Node.js (`npm-package/server/index.js`):**

- ES modules (`"type": "module"`). No CommonJS.
- No new dependencies without discussion — the wrapper must stay thin.
- Preserve binary JSON envelopes verbatim via `envelopeToMcpResult()`.

**JSON envelopes:**

Success: `{ "status": "ok", "data": ... }`
Error: `{ "status": "error", "code": "...", "message": "...", ... }`

Error codes in use: `LIST_NOT_FOUND`, `LIST_AMBIGUOUS`, `REMINDER_NOT_FOUND`, `INVALID_PRIORITY`, `INVALID_FILTER`, `INVALID_PAYLOAD`, `UNKNOWN_COMMAND`, `PERMISSION_DENIED`, `SAVE_FAILED`, `DELETE_FAILED`.

## Running the test matrix locally

```bash
./build.sh binary                                       # compile Swift
./dist/reminders-eventkit list-lists                    # smoke-test
cd npm-package && npm ci --ignore-scripts \
  && REMINDERS_BINARY=$PWD/../dist/reminders-eventkit \
       node -e 'import("./server/index.js")'
~/.local/bin/mcpb validate mcpb/manifest.json           # validate manifest
```

For the MCP Registry manifest:

```bash
# Ensure .claude-plugin/plugin.json exists and is valid JSON
node -e 'JSON.parse(require("fs").readFileSync(".claude-plugin/plugin.json"))'
```

## Continuous integration

Runner time is spent where it pays off, so CI has two tiers:

- **Every pull request** runs `ci.yml`: light checks on Linux, with no Swift build. It lints and cross-checks the manifests, parses the JavaScript and shell scripts, packs the npm tarball, and lists the server's tools over MCP. It only starts when a PR touches files those checks read.
- **Everything that builds the binary** lives in `build.yml`: the universal build, signer checks and smoke tests on Apple Silicon, plus a second job on GitHub's Intel runner (`macos-15-intel`, available until August 2027) that builds natively and runs the binary through the Node server. It never runs on its own. `ci-batch.yml` runs it together with the light checks, by hand against `main` once several merges have landed, and only after a maintainer has approved the run:

  ```bash
  gh workflow run ci-batch.yml --ref main
  ```

  A red batch run means fix or revert before more merges land. Releases are cut only from a `main` commit whose batch run is green. To try a risky change before merging, dispatch the batch against its branch instead of `main`.

## Commit style

- One commit per logical change.
- Subject line: imperative mood, under 72 chars.
- Body: explain *why*, not *what*. Reference issues with `Fixes #123` or `Refs #123`.
- Do not include Claude-generated `Co-Authored-By` unless a human contributor actually reviewed and owns the change.

## Pull requests

1. Fork and branch from `main`.
2. Keep PRs focused — one feature / one fix.
3. Update `CHANGELOG.md` under the `## [Unreleased]` heading.
4. Tests pass locally (`./build.sh && mcpb validate mcpb/manifest.json`).
5. No new runtime dependencies without maintainer agreement.

## Release process

Releases are cut by tagging `main`:

```bash
git tag -a v1.1.0 -m "v1.1.0"
git push origin v1.1.0
```

The `.github/workflows/release.yml` workflow then:

1. Builds the universal Swift binary (arm64 + x86_64) on `macos-14` and refuses to publish one that lacks either slice
2. Imports the `Developer ID Application: high5 ventures GmbH` certificate from `APPLE_CERTIFICATE_P12_BASE64`
3. Signs the binary with Hardened Runtime
4. Packs the `.mcpb`
5. Submits the bundle to Apple's notary service
6. Staples the notarization ticket
7. Publishes to GitHub Releases
8. Publishes the npm package `@high5ventures/apple-reminders-mcp`
9. Publishes the MCP Registry entry `io.github.high5-ventures/apple-reminders`

Only high5 ventures maintainers with access to the Apple Developer account and required GitHub Secrets can cut signed releases.

## License

By contributing, you agree that your contributions will be licensed under the MIT License (see `LICENSE`).
