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
git clone https://github.com/byte5ai/apple-reminders-for-claude.git
cd apple-reminders-for-claude
./build.sh
```

The unified build produces:

- `dist/reminders-eventkit` — unsigned Swift binary for local dev
- `dist/skill/` — skill directory for Claude Code (copy to `~/.claude/skills/apple-reminders/`)
- `dist/apple-reminders.mcpb` — unsigned bundle for Claude Desktop

For signed/notarized release artifacts, see [Release process](#release-process) below — those are built by CI from tagged commits only.

## Project structure

```
src/                    Swift source (single file, EventKit wrapper)
mcpb/                   Claude Desktop / Cowork extension
├── server/index.js     Node.js MCP wrapper
├── manifest.json       MCPB manifest (spec 0.3)
└── package.json        npm deps (MCP SDK)
skills/apple-reminders/ Claude Code skill
├── SKILL.md            Skill definition + protocol docs
├── lib/                Shared AppleScript helpers (flagged fallback only)
└── scripts/            AppleScript fallback scripts
.claude-plugin/         Claude Code Plugin Directory manifest
build.sh                Orchestrator — binary / skill / mcpb / clean / all
.github/workflows/      CI + signed release pipeline
```

## Coding standards

**Swift (`src/reminders-eventkit.swift`):**

- Use `Json.ok()` / `Json.err()` / `Json.errWith()` — never emit ad-hoc JSON.
- Validate command name + arity *before* calling `Store.shared.requestAccessOrExit()` so typos never trigger the TCC prompt.
- Read JSON payloads via stdin when the argv slot is `"-"`. Never parse untrusted content from argv.
- Keep the file single-source, no external Swift packages — simplifies notarization.

**Node.js (`mcpb/server/index.js`):**

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
cd mcpb && npm ci && node -e 'import("./server/index.js")'
~/.local/bin/mcpb validate mcpb/manifest.json           # validate manifest
```

For the MCP Plugin Directory manifest:

```bash
# Ensure .claude-plugin/plugin.json exists and is valid JSON
node -e 'JSON.parse(require("fs").readFileSync(".claude-plugin/plugin.json"))'
```

## Commit style

- One commit per logical change.
- Subject line: imperative mood, under 72 chars.
- Body: explain *why*, not *what*. Reference issues with `Fixes #123` or `Refs #123`.
- Do not include Claude-generated `Co-Authored-By` unless a human contributor actually reviewed and owns the change.

## Pull requests

1. Fork and branch from `main`.
2. Keep PRs focused — one feature / one fix.
3. Update `CHANGELOG.md` under `## [Unreleased]`.
4. Tests pass locally (`./build.sh && mcpb validate mcpb/manifest.json`).
5. No new runtime dependencies without maintainer agreement.

## Release process

Releases are cut by tagging `main`:

```bash
git tag -a v1.1.0 -m "v1.1.0"
git push origin v1.1.0
```

The `.github/workflows/release.yml` workflow then:

1. Builds the Swift binary on `macos-latest`
2. Imports the `Developer ID Application: byte5 GmbH` certificate from `APPLE_CERTIFICATE_P12_BASE64`
3. Signs the binary with Hardened Runtime
4. Packs the `.mcpb`
5. Submits the bundle to Apple's notary service
6. Staples the notarization ticket
7. Publishes to GitHub Releases
8. Publishes the npm package `@byte5ai/apple-reminders-mcp`
9. Publishes the MCP Registry entry `io.github.byte5ai/apple-reminders`

Only byte5 maintainers with access to the Apple Developer account and required GitHub Secrets can cut signed releases.

## License

By contributing, you agree that your contributions will be licensed under the MIT License (see `LICENSE`).
