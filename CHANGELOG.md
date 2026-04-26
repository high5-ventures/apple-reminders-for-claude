# Changelog

All notable changes to this project are documented here. Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this project adheres to [Semantic Versioning](https://semver.org/).

## [1.0.0] — 2026-04-14

First public release under the high5 ventures GmbH open-source umbrella, ready for publication on the Anthropic Desktop Extensions Directory, the Claude Code Plugin Directory, and the MCP Registry.

### Added
- **MCPB manifest v0.3 compliance** with `privacy_policies`, `repository`, `homepage`, `support`, and `icon` metadata.
- **MCP tool annotations** (`readOnlyHint`, `destructiveHint`, `idempotentHint`, `openWorldHint`) on every tool so Claude clients can make informed auto-run decisions.
- **Claude Code Plugin Directory integration** via `.claude-plugin/plugin.json` and the `skills/apple-reminders/` layout.
- **MCP Registry publication** as `io.github.high5-ventures/apple-reminders`, backed by the npm package `@high5ventures/apple-reminders-mcp`.
- **Code signing + notarization** — every release binary carries a `Developer ID Application: high5 ventures GmbH` signature and an Apple-notarized, stapled `.mcpb` bundle.
- **Hardened Runtime** with EventKit entitlements declared in `entitlements.plist`.
- **GitHub Actions release workflow** — tag-triggered, fully automated: build, sign, notarize, staple, GitHub Release, npm publish, MCP Registry publish.
- **PRIVACY.md, SECURITY.md, CONTRIBUTING.md** — full open-source governance set.
- **high5 ventures CI product icon** at 512×512.

### Changed
- Upgraded `@modelcontextprotocol/sdk` from 1.11.3 to 1.29.0.
- Raised minimum Node.js to 18 (aligned with MCP SDK requirements).
- Repository layout: `skill/` → `skills/apple-reminders/` for Plugin Directory conformance.
- `build.sh` now orchestrates signing + notarization when `APPLE_*` environment variables are set; otherwise falls back to an unsigned dev build.

### Security
- All tool payloads for `create_reminder` / `update_reminder` pass through stdin (not argv), eliminating shell-injection surface when the LLM emits untrusted strings.
- Command name + arity validated *before* triggering the macOS TCC prompt — typos no longer cause a bogus permission dialog.
- `package-lock.json` committed; CI uses `npm ci` for deterministic builds.

## [0.1.1] — 2026-04-11

Pre-release hardening from internal code review.

### Added
- `LIST_AMBIGUOUS` error with `candidates` array for disambiguating lists of identical names.
- `INVALID_PAYLOAD` error for unparseable `dueDate` strings.
- stdin `-` sentinel for `create-reminder` / `update-reminder` payloads.
- 30-second timeout on binary invocations in the Node wrapper.

### Changed
- Exit code derivation now parses the JSON `status` field instead of matching strings.
- `priority` / `limit` tool params use `integer` (not `number`) for correct MCP validation.

## [0.1.0] — 2026-04-10

Initial non-public release. Swift/EventKit wrapper, 13 MCP tools, Claude Code skill, Claude Desktop `.mcpb` bundle.

[1.0.0]: https://github.com/high5-ventures/apple-reminders-for-claude/releases/tag/v1.0.0
[0.1.1]: https://github.com/high5-ventures/apple-reminders-for-claude/releases/tag/v0.1.1
[0.1.0]: https://github.com/high5-ventures/apple-reminders-for-claude/releases/tag/v0.1.0
