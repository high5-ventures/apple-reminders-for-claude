# Apple Reminders for Claude

Fast, native Apple Reminders access for Claude — works in **Claude Code** (CLI)
and **Claude Desktop / Cowork** via a single Swift/EventKit binary.

No AppleScript, no indexed positional IDs, no 30-second MCP timeouts. Sub-second
latency on reminder lists with 120+ open items. Full UTF-8 support for German
umlauts, accents, CJK characters, and emoji.

## Why this exists

Existing Apple Reminders integrations for Claude are either:

- **AppleScript-based** — slow (70s+ on large DBs), hits Claude's 30s MCP timeout,
  uses unstable positional indexes, no structured output.
- **Third-party CLI wrappers** (like `reminders-cli`) — no JSON output, still
  use positional indexes.
- **Unsigned community MCP servers** — questionable code hygiene, no clear
  maintenance, often abandoned.

This project wraps Apple's native **EventKit** framework in a single ~500-line
Swift binary that returns structured JSON and stable EventKit UUIDs. Two
distribution artifacts are built from the same source:

| Target | Artifact | Install |
|---|---|---|
| **Claude Code** (CLI) | `dist/skill/` | Copy to `~/.claude/skills/apple-reminders/` |
| **Claude Desktop / Cowork** | `dist/apple-reminders.mcpb` | Double-click to install |

## Features

- **13 MCP tools** covering the full reminder lifecycle: list lists, list reminders
  (open/completed/all), full-text search, today/overdue/scheduled smart queries,
  CRUD on individual reminders.
- **Native EventKit** via Apple's first-party framework — not AppleScript, not
  scraping the Reminders SQLite DB.
- **Stable UUIDs** — reminder IDs survive across sessions, unlike AppleScript
  URIs or CLI positional indexes.
- **Language-neutral** — the skill's `SKILL.md` matches on intent, not keywords,
  so users writing in German, French, Spanish, or any other language are served
  identically. Reminder content is passed through verbatim as UTF-8.
- **Sub-second latency** — full CRUD smoke-test completes in under 1 second on
  a database with 300+ reminders across 10 lists.

## Requirements

- macOS 11 or later (Big Sur and up)
- Apple Swift compiler (`/usr/bin/swiftc`, ships with Xcode Command Line Tools)
- For the `.mcpb` bundle: Claude Desktop
- For the skill: Claude Code CLI

## Build

```bash
# Build everything (Swift binary + skill directory + .mcpb bundle)
./build.sh

# Or individually:
./build.sh binary       # just the Swift binary → dist/reminders-eventkit
./build.sh skill        # Claude Code skill directory → dist/skill/
./build.sh mcpb         # Claude Desktop extension → dist/apple-reminders.mcpb
./build.sh clean        # wipe dist/
```

The `.mcpb` build requires the official MCPB CLI:

```bash
npm install -g @anthropic-ai/mcpb
```

## Install

### Claude Desktop / Cowork (recommended for most users)

```bash
./build.sh mcpb
open dist/apple-reminders.mcpb
```

Claude Desktop shows an installation dialog. Click **Install**, then on the
first tool call, grant Reminders access in the macOS privacy dialog.

### Claude Code CLI

```bash
./build.sh skill
cp -r dist/skill ~/.claude/skills/apple-reminders
```

The skill auto-loads whenever you mention reminders in a Claude Code session,
in any language.

## MCP Tools

All 13 tools accept structured arguments and return a stable JSON envelope
(`{status, data}` on success, `{status, code, message}` on error).

| Tool | Purpose |
|---|---|
| `get_lists` | List all reminder lists with open/completed counts |
| `get_list_info` | Metadata for one list by name |
| `list_reminders` | List reminders in a specific list (open/completed/all) |
| `search_reminders` | Full-text search across all lists |
| `get_today` | Reminders due today |
| `get_overdue` | Overdue open reminders |
| `get_scheduled` | All open reminders with a due date |
| `get_reminder` | Fetch one reminder by ID |
| `create_reminder` | Create a new reminder |
| `update_reminder` | Update an existing reminder |
| `complete_reminder` | Mark as completed |
| `uncomplete_reminder` | Unmark completed |
| `delete_reminder` | Permanently delete |

## Known limitations

- **`flagged` attribute** is not exposed by EventKit. The skill includes an
  AppleScript fallback (`skill/scripts/get_flagged.applescript`) for users who
  absolutely need flagged-reminder queries; the `.mcpb` bundle does not include
  this fallback.
- **List management** (create/rename/delete lists) is not supported in v0.1.
  Create lists manually in Reminders.app once; the tools can then write into
  them freely.
- **Sub-tasks, tags, attachments, recurrence** — all deferred to keep the
  surface area small.

## Architecture

```
Claude Code CLI                   Claude Desktop / Cowork
        │                                   │
        │  (Bash shell)                     │  (stdio MCP)
        │                                   │
        ▼                                   ▼
   reminders-eventkit                 Node.js wrapper
   (single Swift binary)              (server/index.js)
        │                                   │
        │                                   │ (child_process.execFile)
        │                                   ▼
        │                           reminders-eventkit
        │                           (same Swift binary)
        │                                   │
        ▼                                   ▼
              Apple EventKit framework
              (requestFullAccessToReminders)
                       │
                       ▼
              macOS Reminders database
```

One Swift source → one binary → two distribution paths.

## License

Copyright (c) 2026 byte5 GmbH. Released under the MIT License — see [LICENSE](LICENSE).

This project is not affiliated with or endorsed by Apple Inc. or Anthropic PBC.
