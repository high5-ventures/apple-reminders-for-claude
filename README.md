# Apple Reminders for Claude

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![macOS 11+](https://img.shields.io/badge/macOS-11%2B-informational)](https://support.apple.com/macos)
[![Notarized](https://img.shields.io/badge/Apple-Notarized-success)](https://support.apple.com/en-us/HT202491)
[![MCPB manifest](https://img.shields.io/badge/MCPB-0.3-000)](https://github.com/anthropics/mcpb)

Fast, native Apple Reminders access for Claude — works in **Claude Desktop**, **Claude Cowork**, and **Claude Code** (CLI). One signed Swift/EventKit binary, three distribution packages.

No AppleScript, no unstable positional IDs, no 30-second MCP timeouts. Sub-second latency on databases with hundreds of reminders. Full UTF-8 support for German umlauts, accents, CJK characters, and emoji.

**Published by [high5 ventures GmbH](https://h5ventures.de)** — signed with `Developer ID Application: high5 ventures GmbH` and notarized by Apple.

---

## Description

Apple Reminders for Claude gives Claude full CRUD access to your macOS Reminders app. It wraps Apple's native **EventKit** framework in a signed Swift binary that returns stable UUIDs and structured JSON, and ships three ways:

| Target | Artifact | Distribution |
|---|---|---|
| **Claude Desktop / Cowork** | `.mcpb` bundle | Anthropic Desktop Extensions Directory |
| **Claude Code** (CLI) | Plugin with skill | Claude Code Plugin Directory |
| **Any MCP client** | npm package | MCP Registry (`io.github.high5-ventures/apple-reminders`) |

All three paths share the same Swift binary and the same MCP protocol surface, so behavior is identical everywhere.

## Features

- **13 MCP tools** covering the full reminder lifecycle: list lists, list reminders (open/completed/all), full-text search, today/overdue/scheduled smart queries, CRUD on individual reminders.
- **Native EventKit** — not AppleScript, not reverse-engineered SQLite scraping.
- **Stable UUIDs** — reminder IDs survive across sessions, unlike AppleScript URIs or CLI positional indexes.
- **Tool safety annotations** — every tool declares `readOnlyHint` / `destructiveHint` so Claude clients can auto-run queries but prompt for mutations.
- **Language-neutral** — the skill matches on intent, not keywords. Works identically in German, French, Spanish, Japanese, etc.
- **Sub-second latency** — full CRUD smoke-test completes in under 1 s on a database with 300+ reminders across 10 lists.
- **Signed + notarized** — no Gatekeeper warnings, MDM-deployable, enterprise-ready.
- **100% local** — no network I/O. See [PRIVACY.md](PRIVACY.md).

## Installation

### Option 1 — Claude Desktop / Cowork (recommended for most users)

Install from the **Anthropic Desktop Extensions Directory** (in-app search) or download the latest signed `.mcpb` from [Releases](https://github.com/high5-ventures/apple-reminders-for-claude/releases) and double-click it. Claude Desktop shows an install dialog; click **Install**, then on the first tool call, grant Reminders access in the macOS privacy prompt.

### Option 2 — Claude Code CLI

```shell
/plugin install apple-reminders@claude-plugins-official
```

…or add the high5 ventures marketplace directly from GitHub:

```shell
/plugin marketplace add high5-ventures/apple-reminders-for-claude
/plugin install apple-reminders@high5-apple-reminders-for-claude
```

### Option 3 — Any MCP-compatible client (Cursor, Zed, etc.)

```shell
npm install -g @high5ventures/apple-reminders-mcp
```

Then point your client at `@high5ventures/apple-reminders-mcp` as a stdio MCP server. See your client's documentation for configuration specifics.

### Build from source

```shell
git clone https://github.com/high5-ventures/apple-reminders-for-claude.git
cd apple-reminders-for-claude
./build.sh
```

Produces `dist/reminders-eventkit` (binary), `dist/skill/` (Claude Code skill), and `dist/apple-reminders.mcpb` (Claude Desktop bundle). Builds are unsigned; see [CONTRIBUTING.md](CONTRIBUTING.md) for the signed release workflow.

Requirements: macOS 11+, Xcode Command Line Tools, Node.js 18+.

## Configuration

No configuration is required for normal use. The extension runs with these defaults:

| Setting | Default | Notes |
|---|---|---|
| Reminders permission | prompted on first use | Revocable in **System Settings → Privacy & Security → Reminders** |
| Binary timeout (Node wrapper) | 30 s | Hardcoded ceiling; well under any MCP client timeout |
| Response payload cap | 16 MB | Plenty for databases with thousands of reminders |

If you use the npm-distributed server with a non-standard MCP client, set `REMINDERS_BINARY` to the absolute path of the `reminders-eventkit` binary:

```shell
export REMINDERS_BINARY=/absolute/path/to/reminders-eventkit
```

The `.mcpb` and Plugin Directory installations set this variable automatically.

## Usage examples

The skill loads automatically in Claude Code when you mention reminders. In Claude Desktop / Cowork, the tools appear under **Apple Reminders**. You talk to Claude naturally — these examples show what Claude does behind the scenes.

### Example 1 — "What's on my plate today?"

> **You:** Was habe ich heute zu tun?
>
> **Claude** (invokes `get_today`):
> ```json
> { "status": "ok", "data": [
>   { "id": "A1B2…", "name": "Zahnarzt-Termin bestätigen", "list": "Persönlich", "due_date": "2026-04-14T10:00:00" },
>   { "id": "C3D4…", "name": "Rechnung #2026-0412 prüfen", "list": "Arbeit", "due_date": "2026-04-14T14:00:00" }
> ] }
> ```
> **Claude:** Du hast heute zwei offene Erinnerungen: den Zahnarzt-Termin um 10:00 (Persönlich) und die Rechnungs-Prüfung um 14:00 (Arbeit).

### Example 2 — "Add a reminder to the groceries list"

> **You:** Remind me to buy oat milk tomorrow at 6pm.
>
> **Claude** (invokes `create_reminder`):
> ```json
> { "list": "Groceries", "title": "Buy oat milk", "dueDate": "2026-04-15T18:00:00" }
> ```
> **Response:**
> ```json
> { "status": "ok", "data": { "id": "E5F6…", "name": "Buy oat milk", "due_date": "2026-04-15T18:00:00" } }
> ```
> **Claude:** Done — added "Buy oat milk" to Groceries for tomorrow at 18:00.

### Example 3 — "Clean up what's overdue"

> **You:** Show me everything that's overdue, then mark the Slack-DM one as done.
>
> **Claude** (invokes `get_overdue`):
> ```json
> { "status": "ok", "data": [
>   { "id": "G7H8…", "name": "Reply to Alex in Slack DM", "list": "Arbeit", "due_date": "2026-04-12T17:00:00" },
>   { "id": "I9J0…", "name": "Review PR #482", "list": "Arbeit", "due_date": "2026-04-13T12:00:00" }
> ] }
> ```
> **Claude** (invokes `complete_reminder` with `id: "G7H8…"`):
> ```json
> { "status": "ok", "data": { "id": "G7H8…", "completed": true, "completion_date": "2026-04-14T18:22:01" } }
> ```
> **Claude:** Two overdue items: Slack reply (now marked done) and PR #482 review (still open).

## MCP tools

All 13 tools return a stable JSON envelope — `{ "status": "ok", "data": ... }` on success, `{ "status": "error", "code": "...", "message": "..." }` on failure.

| Tool | Annotation | Purpose |
|---|---|---|
| `get_lists` | read-only | List all reminder lists with open/completed counts |
| `get_list_info` | read-only | Metadata for one list by name |
| `list_reminders` | read-only | List reminders in a list (open/completed/all) |
| `search_reminders` | read-only | Full-text search across all lists |
| `get_today` | read-only | Reminders due today |
| `get_overdue` | read-only | Overdue open reminders |
| `get_scheduled` | read-only | All open reminders with a due date |
| `get_reminder` | read-only | Fetch one reminder by ID |
| `create_reminder` | additive | Create a new reminder |
| `update_reminder` | destructive, idempotent | Update an existing reminder |
| `complete_reminder` | destructive, idempotent | Mark as completed |
| `uncomplete_reminder` | destructive, idempotent | Unmark completed |
| `delete_reminder` | destructive, idempotent | Permanently delete |

"Destructive" here follows the MCP specification: it means the operation mutates existing state irreversibly from the user's point of view. Claude clients use these hints to decide when to prompt for confirmation.

## Privacy policy

This extension is **100% local**. No data leaves your Mac via this extension. high5 ventures GmbH operates no server and collects no telemetry.

Read the full policy: [PRIVACY.md](PRIVACY.md).

## Troubleshooting

**"Reminders access denied"** — open **System Settings → Privacy & Security → Reminders** and enable access for Claude Desktop (or your MCP client). Then retry.

**Binary quarantined on first launch** — our releases are signed and notarized, so this should not happen. If it does, verify the signature:

```shell
codesign --verify --verbose /Applications/Claude.app/Contents/Resources/mcpb/apple-reminders/bin/reminders-eventkit
spctl --assess --type execute /Applications/Claude.app/Contents/Resources/mcpb/apple-reminders/bin/reminders-eventkit
```

If either fails, you may have downloaded a tampered copy — re-download from the official [Releases](https://github.com/high5-ventures/apple-reminders-for-claude/releases) page.

**"List not found" or "Multiple lists with that name"** — reminder lists are matched by exact name. Use `get_lists` first to see available names. For duplicates, the error response includes a `candidates` array with stable `calendar_identifier`s; re-call with `id:<calendar_identifier>` as the list argument.

**Flagged reminders return empty** — EventKit does not expose the `flagged` attribute. The Claude Code skill ships an AppleScript fallback (`skills/apple-reminders/scripts/get_flagged.applescript`) for users who need this query. The `.mcpb` bundle does not include this fallback because Claude Desktop does not have shell access.

**Still stuck?** Open an issue → [Support](#support).

## Support

- **Bug reports & feature requests:** <https://github.com/high5-ventures/apple-reminders-for-claude/issues>
- **Security vulnerabilities:** `info@h5ventures.de` — see [SECURITY.md](SECURITY.md)
- **General contact:** `info@h5ventures.de`

## Architecture

```
Claude Desktop / Cowork           Claude Code CLI                Any MCP client (Cursor, Zed, …)
        │                                │                                   │
        │  (stdio MCP)                   │  (Bash via plugin)                │  (stdio MCP)
        ▼                                ▼                                   ▼
    Node wrapper                 reminders-eventkit                    Node wrapper
   (server/index.js)            (Swift binary, direct)               (npm @high5ventures/…)
        │                                │                                   │
        ▼                                │                                   ▼
 reminders-eventkit                      │                          reminders-eventkit
(same Swift binary)                      │                        (downloaded on install)
        │                                │                                   │
        └────────────────────────────────┴───────────────────────────────────┘
                                         │
                                         ▼
                            Apple EventKit framework
                                         │
                                         ▼
                            macOS Reminders database
```

One Swift source → one binary → three distribution paths. See [CONTRIBUTING.md](CONTRIBUTING.md) for build internals.

## License

Copyright © 2026 high5 ventures GmbH. Released under the **MIT License** — see [LICENSE](LICENSE).

This project is not affiliated with or endorsed by Apple Inc. or Anthropic PBC.

"Apple" and "Reminders" are trademarks of Apple Inc. "Claude" is a trademark of Anthropic PBC.
