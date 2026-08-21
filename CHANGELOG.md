# Changelog

All notable changes to this project are documented here. Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Fixed
- **Reminders access was refused without ever showing a dialog** ([#1](https://github.com/high5-ventures/apple-reminders-for-claude/issues/1), [#2](https://github.com/high5-ventures/apple-reminders-for-claude/issues/2)) — macOS attributes a privacy request to the *responsible* process, which for an MCP server is the host application. Claude Desktop declares no Reminders usage description, so `tccd` refused the request before EventKit was reached: no prompt, no entry in System Settings, and `tccutil reset` powerless. The binary now claims TCC responsibility for itself by re-execing with `responsibility_spawnattrs_setdisclaim` (resolved via `dlsym`, degrading to the previous behaviour if a future macOS drops the symbol), carries both `NSRemindersUsageDescription` and `NSRemindersFullAccessUsageDescription` in a linked `__TEXT,__info_plist` section, and ships the `com.apple.security.personal-information.reminders` entitlement that macOS 26+ requires on hardened-runtime binaries. No packaging changes — every install path picks this up from the binary alone.
- **Indefinite hang on an unanswerable access request** — `requestAccessOrExit` waited on a semaphore with no timeout, and a request macOS refuses outright can leave the completion handler unfired. The wait is now bounded (`REMINDERS_TCC_TIMEOUT_SECONDS`, default 120). This is the hang that cancelled every CI run at the 20-minute job timeout; the smoke test is un-quarantined.
- **"User declined Reminders access" reported for refusals nobody declined** — an already-`denied` or `restricted` status now fails fast with the remedy that applies, while a refusal that never produced a dialog reports the new `PERMISSION_UNAVAILABLE` code and states that granting or resetting permissions cannot fix it. Conflating the two is what sent every reporter chasing `tccutil reset`.
- **Signer check rejected every genuine binary** ([#2](https://github.com/high5-ventures/apple-reminders-for-claude/issues/2), [#3](https://github.com/high5-ventures/apple-reminders-for-claude/issues/3)) — both installers verified the signer by grepping `codesign -dv` output for an `Authority=` line, but `codesign` does not print `Authority=` at verbosity 1. The grep could never match, so the Claude Code plugin's SessionStart hook and the npm `postinstall` aborted with `signer mismatch` on every install and on every cached-binary re-verification, despite the downloaded binary being correctly signed and notarized. The `.mcpb` path was unaffected, which is why this went unnoticed. Both installers now evaluate a code-signing requirement (`codesign --verify -R=…`) that pins the Apple anchor, the Developer ID CA, the Developer ID Application leaf, and team `VG5X6JCLGF` — no display-text parsing.
- **Installer diagnostics went to stdout** — the failure dump in `scripts/install-binary.sh` used `2>&1 >&2`, which redirects both streams to stdout rather than stderr, polluting the SessionStart hook's output channel.

### Added
- **`scripts/verify-signature.sh` and `npm-package/scripts/verify-signature.js`** — the signer check as a single, directly invocable entry point per install path, replacing the logic previously inlined in each installer.
- **CI coverage for the signer check** — CI previously only ran `bash -n` over the installer, so the check itself was never executed; that is how the bug above shipped. CI now asserts both installers accept a genuine Developer ID-signed release binary and reject an ad-hoc signed one, and the release workflow gates publishing on the freshly signed binary passing the installers' own check.

## [1.0.3] — 2026-04-27

Visual rebrand to align the product icon with the high5 ventures GmbH brand.

### Changed
- `assets/icon.svg`, `assets/icon.png`, and `mcpb/icon.png` switched from the inherited byte5-CI cyan/blue palette to the high5 ventures orange palette (`#f58220` primary, `#ff9a3e` light) with the h5 signet (`5°`) as the central glyph instead of a generic checkmark.

## [1.0.2] — 2026-04-27

Hardening pass after a full code review of v1.0.1 — no externally observable behaviour changes for end users; several supply-chain, consistency, and documentation fixes.

### Fixed
- **Release pipeline ordering** — the GitHub Release (with the binary asset the npm postinstall fetches) is now created BEFORE the npm package is published. Previously, npm could publish a version whose required binary asset did not yet exist, leaving the immutable npm tarball broken for fresh installs if any post-publish step failed.
- **Server version drift** — `npm-package/server/index.js` reads its version from `package.json` instead of hardcoding it; CI version-consistency check now also covers `mcpb/package.json`.
- **Pre-TCC validation** — invalid filter values, non-integer or negative `limit`, and malformed JSON payloads are now rejected before requesting the macOS TCC permission dialog, so typos no longer leave a ghost permission prompt.
- **Wrapper-level errors envelope** — Node-side timeouts, binary crashes, missing-argument errors, and non-JSON binary output are now surfaced through the same `{status, code, message}` envelope shape as Swift-side errors (new codes: `WRAPPER_TIMEOUT`, `WRAPPER_BINARY_CRASH`, `WRAPPER_EMPTY_OUTPUT`, `WRAPPER_NON_JSON_OUTPUT`, `WRAPPER_ERROR`).
- **Cached-binary signature re-verification** — both installers (`npm-package/scripts/install-binary.js` and `scripts/install-binary.sh`) re-run `codesign --verify` against the cached binary on every invocation, not just at first install; a tampered cached file is detected and replaced.
- **Predictable temp path** — the npm postinstall now uses `mkdtemp()` for the staging path, eliminating a same-user symlink/clobber window. Cleanup runs in a `finally` so partial downloads never persist.
- **`list-lists` output** — now includes `calendar_identifier` so callers receiving a `LIST_NOT_FOUND` for a duplicated list name can disambiguate without a second call.
- **`get-flagged` removed from the Swift binary** — EventKit does not expose the `flagged` attribute, so the command always returned an empty list. The AppleScript fallback in the Claude Code skill remains for users who need flagged queries.

### Security
- **GitHub Actions pinned by SHA** — `actions/checkout`, `actions/setup-node`, and `softprops/action-gh-release` are pinned to commit SHAs (with the human-readable version retained in a comment).
- **`mcp-publisher` pinned and checksum-verified** — fetched from a tagged version (v1.7.0) and verified against a known-good SHA-256 before execution.
- **Apple credentials scoped to step** — `APPLE_ID`, `APPLE_APP_SPECIFIC_PASSWORD`, and `APPLE_TEAM_ID` are now exposed only to the notarization step instead of the entire release job.

### Documentation
- README, CONTRIBUTING, PRIVACY, and SECURITY updated to match the actual repository layout (the canonical Node MCP server lives in `npm-package/server/`; `mcpb/server/` no longer exists) and to clarify the install-time GitHub-Releases download relative to the "no network I/O" runtime guarantee.
- README response examples now reflect the actual envelope shape (`data.reminders[]` for queries that return collections, `data.reminder` for single-item operations).

## [1.0.1] — 2026-04-26

Hotfix for MCP Registry validation on first publish — the v1.0.0 npm package and GitHub Release are valid; only the MCP Registry submission failed.

### Fixed
- `npm-package/server.json` description trimmed to ≤100 characters as required by MCP Registry validation (was 105).
- `src/entitlements.plist` no longer contains XML comments — Apple's `AMFIUnserializeXML` (used by `codesign`) rejected them while `plutil` accepted them silently.
- `scripts/notarize.sh` skips `xcrun stapler` for `.mcpb` files (Apple's stapler does not support that bundle format); notarization ticket is resolved online instead.

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

[Unreleased]: https://github.com/high5-ventures/apple-reminders-for-claude/compare/v1.0.3...HEAD
[1.0.3]: https://github.com/high5-ventures/apple-reminders-for-claude/releases/tag/v1.0.3
[1.0.2]: https://github.com/high5-ventures/apple-reminders-for-claude/releases/tag/v1.0.2
[1.0.1]: https://github.com/high5-ventures/apple-reminders-for-claude/releases/tag/v1.0.1
[1.0.0]: https://github.com/high5-ventures/apple-reminders-for-claude/releases/tag/v1.0.0
[0.1.1]: https://github.com/high5-ventures/apple-reminders-for-claude/releases/tag/v0.1.1
[0.1.0]: https://github.com/high5-ventures/apple-reminders-for-claude/releases/tag/v0.1.0
