# Apple Reminders for Claude

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![macOS 11+](https://img.shields.io/badge/macOS-11%2B-informational)](https://support.apple.com/macos)
[![Notarized](https://img.shields.io/badge/Apple-Notarized-success)](https://support.apple.com/en-us/HT202491)
[![MCPB manifest](https://img.shields.io/badge/MCPB-0.3-000)](https://github.com/anthropics/mcpb)

Fast, native Apple Reminders access for Claude — works in **Claude Desktop**, **Claude Cowork**, and **Claude Code** (CLI). One signed Swift/EventKit binary, three distribution packages.

No AppleScript, no unstable positional IDs, no 30-second MCP timeouts. Sub-second latency on databases with hundreds of reminders. Full UTF-8 support for German umlauts, accents, CJK characters, and emoji.

**Published by [high5 ventures GmbH](https://h5ventures.de)** — signed with `Developer ID Application: high5 ventures GmbH` and notarized by Apple.

---

## Quick start

You need a Mac running macOS 11 or later, and Claude Desktop.

1. Download **`apple-reminders.mcpb`** from the [latest release](https://github.com/high5-ventures/apple-reminders-for-claude/releases/latest).
2. Double-click it. Claude Desktop opens an install dialog — click **Install**.
3. Ask Claude something like **"What's on my reminders for today?"**

macOS asks for Reminders access on that first question. Allow it, and you are done — Claude can now read and change your reminders.

Updating later is the same three steps: download the newer `.mcpb`, double-click, install.

> Using something other than Claude Desktop? See [Installation](#installation) for Claude Code and other MCP clients.

---

## Contents

- [Description](#description)
- [Features](#features)
- [Usage examples](#usage-examples)
- [Installation](#installation)
- [Configuration](#configuration)
- [MCP tools](#mcp-tools)
- [Privacy policy](#privacy-policy)
- [Troubleshooting](#troubleshooting)
- [Support](#support)
- [Architecture](#architecture)
- [License](#license)

---

## Description

Apple Reminders for Claude gives Claude full CRUD access to your macOS Reminders app. It wraps Apple's native **EventKit** framework in a signed Swift binary that returns stable UUIDs and structured JSON, and ships three ways:

| Target | Artifact | Where to get it |
|---|---|---|
| **Claude Desktop / Cowork** | `.mcpb` bundle | [Releases](https://github.com/high5-ventures/apple-reminders-for-claude/releases) |
| **Claude Code** (CLI) | Plugin with skill | `/plugin marketplace add` against this repository |
| **Any MCP client** | npm package | `npm install -g @high5ventures/apple-reminders-mcp` |

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

## Usage examples

The skill loads automatically in Claude Code when you mention reminders. In Claude Desktop / Cowork, the tools appear under **Apple Reminders**. You talk to Claude naturally — these examples show what Claude does behind the scenes.

### Example 1 — "What's on my plate today?"

> **You:** Was habe ich heute zu tun?
>
> **Claude** (invokes `get_today`):
> ```json
> { "status": "ok", "data": { "reminders": [
>   { "id": "A1B2…", "name": "Zahnarzt-Termin bestätigen", "list": "Persönlich", "due_date": "2026-04-14T10:00:00" },
>   { "id": "C3D4…", "name": "Rechnung #2026-0412 prüfen", "list": "Arbeit", "due_date": "2026-04-14T14:00:00" }
> ] } }
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
> { "status": "ok", "data": { "reminder": { "id": "E5F6…", "name": "Buy oat milk", "due_date": "2026-04-15T18:00:00" } } }
> ```
> **Claude:** Done — added "Buy oat milk" to Groceries for tomorrow at 18:00.

### Example 3 — "Clean up what's overdue"

> **You:** Show me everything that's overdue, then mark the Slack-DM one as done.
>
> **Claude** (invokes `get_overdue`):
> ```json
> { "status": "ok", "data": { "reminders": [
>   { "id": "G7H8…", "name": "Reply to Alex in Slack DM", "list": "Work", "due_date": "2026-04-12T17:00:00" },
>   { "id": "I9J0…", "name": "Review PR #482", "list": "Work", "due_date": "2026-04-13T12:00:00" }
> ] } }
> ```
> **Claude** (invokes `complete_reminder` with `id: "G7H8…"`):
> ```json
> { "status": "ok", "data": { "reminder": { "id": "G7H8…", "completed": true, "completion_date": "2026-04-14T18:22:01" } } }
> ```
> **Claude:** Two overdue items: Slack reply (now marked done) and PR #482 review (still open).

## Installation

### Claude Desktop / Cowork

Download `apple-reminders.mcpb` from [Releases](https://github.com/high5-ventures/apple-reminders-for-claude/releases) and double-click it. Claude Desktop shows an install dialog; click **Install**, then grant Reminders access in the macOS privacy prompt on the first tool call.

**Updating works exactly the same way** — download the newer `.mcpb` and double-click it.

This is how the extension is installed. The two sections below cover other MCP clients; on a Mac with Claude Desktop you do not need them.

### Claude Code (CLI)

```shell
/plugin marketplace add high5-ventures/apple-reminders-for-claude
```

Reload Claude Code before installing — the plugin only becomes visible once the
newly added marketplace has been picked up.

```shell
/plugin install apple-reminders@high5-apple-reminders-for-claude
```

More steps than the `.mcpb` double-click, and worth it for one reason: new
versions are offered automatically from then on. You still have to look and
confirm — nothing updates itself.

### Any other MCP client (Cursor, Zed, …)

```shell
npm install -g @high5ventures/apple-reminders-mcp
```

Then add it to your client's MCP configuration:

```json
{
  "mcpServers": {
    "apple-reminders": {
      "command": "apple-reminders-mcp"
    }
  }
}
```

Or skip the global install and let the client fetch it on demand:

```json
{
  "mcpServers": {
    "apple-reminders": {
      "command": "npx",
      "args": ["-y", "@high5ventures/apple-reminders-mcp"]
    }
  }
}
```

Where that configuration lives differs per client — see your client's documentation for the file path.

### Build from source

```shell
git clone https://github.com/high5-ventures/apple-reminders-for-claude.git
cd apple-reminders-for-claude
./build.sh
```

Produces `dist/reminders-eventkit` (binary), `dist/skill/` (Claude Code skill), and `dist/apple-reminders.mcpb` (Claude Desktop bundle). Builds are unsigned; see [CONTRIBUTING.md](CONTRIBUTING.md) for the signed release workflow.

Requirements for building: macOS 11+, Xcode Command Line Tools, Node.js 18+.

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

The `.mcpb` and Claude Code plugin installations set this variable automatically.

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

This extension is **100% local at runtime** — no data leaves your Mac via this extension. high5 ventures GmbH operates no server and collects no telemetry. The only network activity is the one-time download of the signed Swift binary from GitHub Releases during install (verified by Apple Developer ID signature, refuses to install on mismatch).

Read the full policy: [PRIVACY.md](PRIVACY.md).

## Troubleshooting

**`PERMISSION_DENIED`** — you (or a device policy) turned Reminders access off. Re-enable it in **System Settings → Privacy & Security → Reminders**, then retry.

**`PERMISSION_UNAVAILABLE`** — a different problem, and the one worth reading carefully: macOS refused the request *without ever showing a dialog*, so there is nothing to switch on and the privacy pane stays empty. Granting permissions or running `tccutil reset` cannot help — there is no entry to grant or reset.

macOS attributes a privacy request to the *responsible* process, which for an MCP server is normally the application that launched it. If that application declares no Reminders usage description, the request is refused before it reaches EventKit. Since v1.0.4 the binary claims TCC responsibility for itself, so macOS reads the usage description from the binary and can prompt regardless of the host — if you still see this error, check which process macOS holds responsible:

```shell
log show --last 3m --predicate 'process == "tccd"' --info --debug | grep -i reminder
```

The `AttributionChain` line should name `reminders-eventkit` as `responsible`. If it names the host application instead, the self-attribution did not take effect — please include that log line when opening an issue.

**Binary quarantined on first launch** — our releases are signed and notarized, so this should not happen. If it does, verify the signature:

```shell
BIN=~/Library/Application\ Support/Claude/Claude\ Extensions/local.mcpb.high5-ventures-gmbh.apple-reminders/bin/reminders-eventkit
codesign --verify --verbose "$BIN"
spctl --assess --type execute "$BIN"
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
