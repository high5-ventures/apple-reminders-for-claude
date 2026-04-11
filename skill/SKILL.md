---
name: apple-reminders
description: Read and write Apple Reminders on macOS with sub-second latency via a self-contained EventKit binary. Use this skill whenever the user wants to list, create, update, complete, or delete reminders, inspect reminder lists, or run smart queries (today, overdue, scheduled, full-text search). Works with any UI language — match on intent, not keywords.
---

# Apple Reminders

This skill wraps a small, self-contained Swift binary (`reminders-eventkit`) that speaks Apple's EventKit framework directly. It is 10-200× faster than the AppleScript alternative and returns structured JSON for every operation. The skill never improvises AppleScript at runtime — every call is a single shell invocation against the binary.

**Language neutrality.** This skill is intentionally language-agnostic. Match the user's intent, not specific keywords — a user writing in German ("Leg mir eine Erinnerung an"), French ("Ajoute un rappel"), Spanish, or any other language should be served identically. Reply to the user in whatever language they wrote in. Reminder content (titles, notes, list names) is passed through verbatim as UTF-8; umlauts, accents, CJK characters, and emoji work without special handling.

## When to use this skill

Load this skill whenever the user's intent involves Apple Reminders: listing or inspecting reminder lists, creating/updating/completing/deleting individual reminders, or running smart queries across lists (what's due today, what's overdue, what's currently scheduled, full-text search). This applies regardless of the language the user writes in.

Do **not** use this skill for Calendar events, Notes, Mail, or Contacts — those belong to separate skills.

## Prerequisites

- macOS with the Reminders app present.
- The compiled binary at `bin/reminders-eventkit` (relative to this skill directory). If it's missing, see the "Rebuilding the binary" section below.
- The `Bash` tool must be available. This skill does **not** use the `mcp__Control_your_Mac__osascript` tool — the EventKit binary is called directly via Bash, which has no 30-second timeout.
- On first run, macOS shows a Privacy permission dialog for Reminders access. The user grants it once and it persists until revoked in *System Settings → Privacy & Security → Reminders*.

## Execution protocol

Every function is a single shell invocation. Do not deviate.

1. **Pick the command** from the catalog below based on the user's intent.
2. **Invoke the binary** via the `Bash` tool:
   ```bash
   ~/.claude/skills/apple-reminders/bin/reminders-eventkit <command> [args...]
   ```
3. **Parse the stdout** — exactly one line of JSON is printed. It's always one of:
   - `{"status":"ok","data": <payload>}` — success.
   - `{"status":"error","code":"<TOKEN>","message":"<text>"}` — failure.
4. **Exit code** matches: `0` for ok, `1` for error. You can rely on either signal.
5. **Present the result** to the user in their language. Never leak the raw JSON unless they asked for it.

## Argument encoding rules

Commands that take structured data use JSON payloads as a single positional argument. Commands that take simple scalars use plain positional arguments.

**JSON payload arguments** (for `create-reminder`, `update-reminder`): quote the whole JSON string once with shell single quotes. Embed double-quoted JSON keys and string values normally. Example:
```bash
reminders-eventkit create-reminder '{"list":"Groceries","title":"Buy milk","dueDate":"2026-04-11T18:00:00","priority":5}'
```

**Scalar arguments** (list names, IDs, filters): quote each with double quotes to handle spaces and special characters safely. Example:
```bash
reminders-eventkit list-reminders "Reise und Freizeit" "open"
```

**Date format**: ISO-8601 local time, seconds precision, no timezone suffix: `2026-04-11T18:00:00`. The binary also accepts full ISO-8601 with timezone offset if you need to be explicit. Never pass natural-language date strings — parse those yourself first.

## Command catalog

| Command | Arguments | Returns (on success) |
|---|---|---|
| `list-lists` | — | `{"lists":[{"name","account","open_count","completed_count"}]}` |
| `get-list-info` | `<listName>` | `{"name","account","open_count","completed_count"}` |
| `list-reminders` | `<listName> <filter>` | `{"reminders":[<reminder>...]}` |
| `search-reminders` | `<query> <filter> <limit>` | `{"reminders":[<reminder>...]}` |
| `get-today` | — | `{"reminders":[<reminder>...]}` |
| `get-overdue` | — | `{"reminders":[<reminder>...]}` |
| `get-scheduled` | — | `{"reminders":[<reminder>...]}` |
| `get-flagged` | — | `{"reminders":[], "warning":"..."}` — see note below |
| `get-reminder` | `<id>` | `{"reminder": <reminder>}` |
| `create-reminder` | `<json-payload>` | `{"reminder": <reminder>}` |
| `update-reminder` | `<json-payload>` | `{"reminder": <reminder>}` |
| `complete-reminder` | `<id>` | `{"reminder": <reminder>}` |
| `uncomplete-reminder` | `<id>` | `{"reminder": <reminder>}` |
| `delete-reminder` | `<id>` | `{"deleted_id": "..."}` |

### Filter values

`<filter>` is always exactly one of: `open`, `completed`, `all`. Any other value returns `INVALID_FILTER`.

### create-reminder payload

```json
{
  "list": "Groceries",                   // required
  "title": "Buy milk",                   // required
  "body": "organic, 1.5l",               // optional
  "dueDate": "2026-04-11T18:00:00",      // optional, ISO-8601
  "priority": 5,                         // optional, one of 0|1|5|9, default 0
  "flagged": false                       // accepted but ignored — see flagged note
}
```

### update-reminder payload

```json
{
  "id": "B769EAF1-7271-4EE7-B228-8A0FD6B65B47",  // required
  "title": "...",                        // optional, replaces
  "body": "...",                         // optional, replaces
  "dueDate": "2026-04-11T18:00:00",      // optional, replaces
  "clearDueDate": true,                  // optional, wipes due date explicitly
  "priority": 5,                         // optional
  "flagged": true                        // accepted but ignored — see flagged note
}
```

Use `clearDueDate: true` to distinguish "remove the due date" from "leave unchanged" (which is what happens when you omit `dueDate`).

### Reminder schema (returned by every read function)

```json
{
  "id": "B769EAF1-7271-4EE7-B228-8A0FD6B65B47",
  "name": "Buy milk",
  "body": "organic, 1.5l",
  "due_date": "2026-04-11T18:00:00",
  "remind_me_date": "2026-04-11T18:00:00",
  "completed": false,
  "completion_date": null,
  "priority": 5,
  "flagged": false,
  "list": "Groceries"
}
```

Optional fields are `null` when not set. Field names are stable — the skill and any downstream consumers can depend on them.

## Known limitations

### `flagged` is not readable or writable via EventKit

Apple's EventKit framework does not expose the "flagged" attribute that the Reminders UI shows. `get-flagged` always returns an empty array with a `warning` field. `create-reminder` and `update-reminder` accept `flagged` in the payload for API stability but silently ignore it. If the user explicitly needs flagged queries, tell them this limitation and offer to fall back to the AppleScript path described below.

### Completed-count may differ from the Reminders UI

EventKit returns the true completed count from the database. The Reminders app UI may hide completed items based on a user preference (*Reminders → Settings → Show → Completed: All / Last 30 Days / ...*). If the user is surprised by a high `completed_count`, point them at that setting.

### Creating, renaming, or deleting **lists** is not supported

v1 is read/write on reminders within existing lists only. List management (create/rename/delete) would require additional EventKit calls and is deliberately deferred to keep the binary small. If the user asks to create a list, tell them to create it manually in the Reminders app once, then the skill can write into it freely.

### Sub-tasks, tags, attachments, and recurrence are not supported

Same reasoning — deferred to keep the surface area small. Sub-tasks in particular require the macOS 13+ subreminder API and careful parent-child handling.

## AppleScript fallback for `flagged`

If the user absolutely needs flagged-reminder queries, there is a pre-built AppleScript template at `scripts/get_flagged.applescript` plus a prelude at `lib/_prelude.applescript` that together implement this one missing function via the `Control your Mac` MCP. Read both files, concatenate (body + prelude), and send via `mcp__Control_your_Mac__osascript`. This fallback is **only** for `get-flagged` and is slow on large databases — use it sparingly.

## Rebuilding the binary

If the binary at `bin/reminders-eventkit` is missing, corrupted, or outdated, rebuild it:

```bash
swiftc -O \
  ~/.claude/skills/apple-reminders/src/reminders-eventkit.swift \
  -o ~/.claude/skills/apple-reminders/bin/reminders-eventkit
```

Requirements:
- Apple Swift compiler (`/usr/bin/swiftc`, ships with macOS command-line tools)
- macOS 11+ (uses `requestFullAccessToReminders` on macOS 14+ with a fallback for older versions)

The source is a single ~500-line Swift file under `src/reminders-eventkit.swift`. Read it before rebuilding if you need to audit what the binary does.

## Error codes

- `LIST_NOT_FOUND` — the named list doesn't exist. Run `list-lists` to show the user what's available.
- `REMINDER_NOT_FOUND` — the ID is unknown. Usually means a stale ID from a previous session; re-query.
- `INVALID_PRIORITY` — priority was not one of `0|1|5|9`.
- `INVALID_FILTER` — filter was not one of `open|completed|all`.
- `INVALID_PAYLOAD` — the JSON payload couldn't be parsed or was missing a required field. The message says which.
- `PERMISSION_DENIED` — macOS refused Reminders access. Tell the user to approve it in *System Settings → Privacy & Security → Reminders*.
- `SAVE_FAILED` / `DELETE_FAILED` — EventKit refused the write. Rare; usually transient. Retry once, then show the user the raw message.

## Worked example

User: *"Add 'Buy milk' to my Groceries list for tomorrow at 6 PM, note: 'organic, 1.5l'."*

```bash
~/.claude/skills/apple-reminders/bin/reminders-eventkit create-reminder '{"list":"Groceries","title":"Buy milk","body":"organic, 1.5l","dueDate":"2026-04-12T18:00:00","priority":0}'
```

Response:
```json
{"status":"ok","data":{"reminder":{"id":"...","name":"Buy milk","body":"organic, 1.5l","due_date":"2026-04-12T18:00:00",...}}}
```

Confirm to the user in their language, e.g. *"Done — 'Buy milk' ist auf deiner Groceries-Liste, fällig morgen 18 Uhr."*
