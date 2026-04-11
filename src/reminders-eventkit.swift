// Copyright (c) 2026 byte5 GmbH
// SPDX-License-Identifier: MIT
//
// reminders-eventkit.swift
//
// A small, self-contained CLI wrapper around Apple's EventKit framework that
// exposes CRUD operations and smart queries for macOS Reminders. It is used
// by the `apple-reminders` Claude skill as a fast, structured alternative to
// AppleScript (EventKit is indexed, AppleScript scans linearly).
//
// Build:
//   swiftc -O reminders-eventkit.swift -o reminders-eventkit
//
// Usage:
//   reminders-eventkit <command> [args...]
//
// Commands (all arguments are positional JSON strings when they contain
// structured data; simple scalars are plain):
//
//   list-lists
//   get-list-info     <list-name>
//   list-reminders    <list-name> <filter:open|completed|all>
//   search-reminders  <query> <filter:open|completed|all> <limit:int>
//   get-today
//   get-overdue
//   get-scheduled
//   get-flagged
//   get-reminder      <id>
//   create-reminder   <json-payload>
//   update-reminder   <json-payload>
//   complete-reminder <id>
//   uncomplete-reminder <id>
//   delete-reminder   <id>
//
// JSON payloads for create/update use this shape (all fields optional except
// where noted):
//
//   create:
//     { "list": "Groceries",      // required
//       "title": "Buy milk",      // required
//       "body": "organic, 1.5l",
//       "dueDate": "2026-04-11T18:00:00",  // ISO-8601 local or with offset
//       "priority": 5,            // 0|1|5|9
//       "flagged": false }
//
//   update:
//     { "id": "UUID",             // required
//       "title": "...",
//       "body": "...",
//       "dueDate": "...",
//       "clearDueDate": true,     // explicit wipe
//       "priority": 5,
//       "flagged": true }
//
// Every invocation prints exactly one line of JSON to stdout:
//
//   {"status":"ok","data": <payload>}
//   {"status":"error","code":"<TOKEN>","message":"<text>"}
//
// Exit code is 0 for "ok", 1 for "error". The wrapper never writes to stderr
// on its happy path; unexpected crashes land in stderr with a Swift backtrace.

import Foundation
import EventKit

// MARK: - JSON helpers ------------------------------------------------------

/// Minimal JSON encoder that uses Foundation's JSONSerialization but wraps it
/// in a stable shape and handles ISO-8601 dates ourselves because
/// JSONSerialization cannot encode Dates.

enum Json {
    /// Encode `Any`-typed value tree to a compact JSON string.
    static func encode(_ value: Any) -> String {
        do {
            let data = try JSONSerialization.data(
                withJSONObject: value,
                options: [.withoutEscapingSlashes]
            )
            return String(data: data, encoding: .utf8) ?? "null"
        } catch {
            return "null"
        }
    }

    static func ok(_ payload: Any) -> String {
        return encode(["status": "ok", "data": payload])
    }

    static func err(code: String, message: String) -> String {
        return encode(["status": "error", "code": code, "message": message])
    }
}

/// Stable ISO-8601 formatter (local time zone, seconds precision, no TZ
/// suffix to match the AppleScript reference implementation).
let isoFormatter: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = TimeZone.current
    f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
    return f
}()

/// Parser that accepts either the local format above OR a full ISO-8601 with
/// TZ offset, for flexibility on input.
func parseDate(_ s: String) -> Date? {
    if let d = isoFormatter.date(from: s) { return d }
    let iso = ISO8601DateFormatter()
    iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let d = iso.date(from: s) { return d }
    iso.formatOptions = [.withInternetDateTime]
    return iso.date(from: s)
}

// MARK: - Reminder serialisation -------------------------------------------

/// Convert an EKReminder to a dictionary matching the skill's JSON schema.
/// Keep field names identical to the AppleScript implementation so existing
/// SKILL.md documentation stays accurate.
func reminderDict(_ r: EKReminder) -> [String: Any] {
    var dict: [String: Any] = [
        "id": r.calendarItemIdentifier,
        "name": r.title ?? "",
        "body": r.notes ?? NSNull(),
        "completed": r.isCompleted,
        "priority": r.priority,
        "flagged": false,  // EKReminder has no `flagged` attribute; see note
        "list": r.calendar?.title ?? NSNull(),
    ]

    // Due date comes from dueDateComponents, not a Date directly.
    if let dc = r.dueDateComponents, let d = Calendar.current.date(from: dc) {
        dict["due_date"] = isoFormatter.string(from: d)
    } else {
        dict["due_date"] = NSNull()
    }

    // remind_me_date: EventKit uses alarms for this. We expose the first
    // absolute-date alarm if any.
    if let alarms = r.alarms,
       let firstAbs = alarms.first(where: { $0.absoluteDate != nil }),
       let d = firstAbs.absoluteDate
    {
        dict["remind_me_date"] = isoFormatter.string(from: d)
    } else {
        dict["remind_me_date"] = NSNull()
    }

    if let cd = r.completionDate {
        dict["completion_date"] = isoFormatter.string(from: cd)
    } else {
        dict["completion_date"] = NSNull()
    }

    return dict
}

// NOTE on `flagged`:
// EKReminder does not expose the "flagged" property that AppleScript does,
// because "flagged" is implemented on top of tasks, not calendar items, in
// newer macOS versions. We report `false` for all reminders and document the
// limitation. If the user needs flagged queries, the AppleScript path
// remains available. (A future improvement could look for a "#flagged" tag
// or the private `_flagged` KVC path, but neither is stable across macOS
// releases.)

// MARK: - Store access ------------------------------------------------------

/// Lazy, cached EKEventStore. Request access synchronously on first use.
/// We exit with PERMISSION_DENIED if the user declines.
final class Store {
    static let shared = Store()
    let store: EKEventStore

    private init() {
        self.store = EKEventStore()
    }

    /// Request full access to reminders. Blocks until the user responds to
    /// the system dialog (first run only).
    func requestAccessOrExit() {
        let sem = DispatchSemaphore(value: 0)
        var granted = false
        var failure: Error?

        if #available(macOS 14.0, *) {
            store.requestFullAccessToReminders { ok, err in
                granted = ok
                failure = err
                sem.signal()
            }
        } else {
            store.requestAccess(to: .reminder) { ok, err in
                granted = ok
                failure = err
                sem.signal()
            }
        }

        sem.wait()

        if !granted {
            let msg = failure?.localizedDescription
                ?? "User declined Reminders access."
            print(Json.err(code: "PERMISSION_DENIED", message: msg))
            exit(1)
        }
    }

    /// Fetch all calendars of type .reminder.
    func lists() -> [EKCalendar] {
        return store.calendars(for: .reminder)
    }

    /// Find a calendar by exact title.
    func list(named name: String) -> EKCalendar? {
        return lists().first(where: { $0.title == name })
    }

    /// Fetch reminders matching a predicate, synchronously.
    func fetch(_ predicate: NSPredicate) -> [EKReminder] {
        let sem = DispatchSemaphore(value: 0)
        var result: [EKReminder] = []
        store.fetchReminders(matching: predicate) { reminders in
            result = reminders ?? []
            sem.signal()
        }
        sem.wait()
        return result
    }

    /// Find a reminder by its EventKit identifier (`calendarItemIdentifier`).
    /// EventKit has no direct lookup, so we scan all reminders. That's still
    /// O(n) but indexed by the framework and vastly faster than the
    /// AppleScript equivalent.
    func reminder(id: String) -> EKReminder? {
        let predicate = store.predicateForReminders(in: nil)
        return fetch(predicate).first(where: { $0.calendarItemIdentifier == id })
    }
}

// MARK: - Commands ----------------------------------------------------------

enum Command {
    static func listLists() -> String {
        let cals = Store.shared.lists()
        var out: [[String: Any]] = []
        for cal in cals {
            // open/completed counts via predicates
            let store = Store.shared.store
            let openPred = store.predicateForIncompleteReminders(
                withDueDateStarting: nil, ending: nil, calendars: [cal]
            )
            let donePred = store.predicateForCompletedReminders(
                withCompletionDateStarting: nil, ending: nil, calendars: [cal]
            )
            let openCount = Store.shared.fetch(openPred).count
            let doneCount = Store.shared.fetch(donePred).count
            out.append([
                "name": cal.title,
                "account": cal.source?.title ?? NSNull(),
                "open_count": openCount,
                "completed_count": doneCount,
            ])
        }
        return Json.ok(["lists": out])
    }

    static func getListInfo(_ name: String) -> String {
        guard let cal = Store.shared.list(named: name) else {
            return Json.err(
                code: "LIST_NOT_FOUND",
                message: "No reminder list named '\(name)'."
            )
        }
        let store = Store.shared.store
        let openPred = store.predicateForIncompleteReminders(
            withDueDateStarting: nil, ending: nil, calendars: [cal]
        )
        let donePred = store.predicateForCompletedReminders(
            withCompletionDateStarting: nil, ending: nil, calendars: [cal]
        )
        let openCount = Store.shared.fetch(openPred).count
        let doneCount = Store.shared.fetch(donePred).count
        return Json.ok([
            "name": cal.title,
            "account": cal.source?.title ?? NSNull(),
            "open_count": openCount,
            "completed_count": doneCount,
        ])
    }

    static func listReminders(_ listName: String, _ filter: String) -> String {
        guard let cal = Store.shared.list(named: listName) else {
            return Json.err(
                code: "LIST_NOT_FOUND",
                message: "No reminder list named '\(listName)'."
            )
        }
        let store = Store.shared.store
        let pred: NSPredicate
        switch filter {
        case "open":
            pred = store.predicateForIncompleteReminders(
                withDueDateStarting: nil, ending: nil, calendars: [cal]
            )
        case "completed":
            pred = store.predicateForCompletedReminders(
                withCompletionDateStarting: nil, ending: nil, calendars: [cal]
            )
        case "all":
            pred = store.predicateForReminders(in: [cal])
        default:
            return Json.err(
                code: "INVALID_FILTER",
                message: "Filter must be one of open|completed|all."
            )
        }
        let items = Store.shared.fetch(pred).map(reminderDict)
        return Json.ok(["reminders": items])
    }

    static func searchReminders(
        _ query: String, _ filter: String, _ limit: Int
    ) -> String {
        let store = Store.shared.store
        let pred: NSPredicate
        switch filter {
        case "open":
            pred = store.predicateForIncompleteReminders(
                withDueDateStarting: nil, ending: nil, calendars: nil
            )
        case "completed":
            pred = store.predicateForCompletedReminders(
                withCompletionDateStarting: nil, ending: nil, calendars: nil
            )
        case "all":
            pred = store.predicateForReminders(in: nil)
        default:
            return Json.err(
                code: "INVALID_FILTER",
                message: "Filter must be one of open|completed|all."
            )
        }
        let needle = query.lowercased()
        var hits: [EKReminder] = []
        for r in Store.shared.fetch(pred) {
            let title = (r.title ?? "").lowercased()
            let body = (r.notes ?? "").lowercased()
            if title.contains(needle) || body.contains(needle) {
                hits.append(r)
                if limit > 0 && hits.count >= limit { break }
            }
        }
        return Json.ok(["reminders": hits.map(reminderDict)])
    }

    static func getToday() -> String {
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        let end = cal.date(byAdding: .day, value: 1, to: start)!
            .addingTimeInterval(-1)
        let pred = Store.shared.store.predicateForIncompleteReminders(
            withDueDateStarting: start, ending: end, calendars: nil
        )
        let items = Store.shared.fetch(pred).map(reminderDict)
        return Json.ok(["reminders": items])
    }

    static func getOverdue() -> String {
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        // ending at `start` means strictly before today 00:00.
        let pred = Store.shared.store.predicateForIncompleteReminders(
            withDueDateStarting: nil, ending: start.addingTimeInterval(-1),
            calendars: nil
        )
        let items = Store.shared.fetch(pred).map(reminderDict)
        return Json.ok(["reminders": items])
    }

    static func getScheduled() -> String {
        // All incomplete reminders with any due date. EventKit's predicate
        // doesn't distinguish "has a due date" from "has no due date", so we
        // post-filter.
        let pred = Store.shared.store.predicateForIncompleteReminders(
            withDueDateStarting: nil, ending: nil, calendars: nil
        )
        let items = Store.shared.fetch(pred)
            .filter { $0.dueDateComponents != nil }
            .map(reminderDict)
        return Json.ok(["reminders": items])
    }

    static func getFlagged() -> String {
        // See note above on EKReminder.flagged. Returns an empty array with
        // a warning field so Claude can report this clearly to the user.
        return Json.ok([
            "reminders": [] as [Any],
            "warning": "EventKit does not expose the 'flagged' attribute on reminders. Use the AppleScript fallback for flagged queries.",
        ])
    }

    static func getReminder(_ id: String) -> String {
        guard let r = Store.shared.reminder(id: id) else {
            return Json.err(
                code: "REMINDER_NOT_FOUND",
                message: "No reminder with id '\(id)'."
            )
        }
        return Json.ok(["reminder": reminderDict(r)])
    }

    static func createReminder(_ payloadJson: String) -> String {
        guard let data = payloadJson.data(using: .utf8),
              let raw = try? JSONSerialization.jsonObject(with: data),
              let obj = raw as? [String: Any]
        else {
            return Json.err(
                code: "INVALID_PAYLOAD",
                message: "Payload must be a JSON object."
            )
        }
        guard let listName = obj["list"] as? String else {
            return Json.err(
                code: "INVALID_PAYLOAD",
                message: "Missing required field 'list'."
            )
        }
        guard let title = obj["title"] as? String else {
            return Json.err(
                code: "INVALID_PAYLOAD",
                message: "Missing required field 'title'."
            )
        }
        guard let cal = Store.shared.list(named: listName) else {
            return Json.err(
                code: "LIST_NOT_FOUND",
                message: "No reminder list named '\(listName)'."
            )
        }

        let priority = obj["priority"] as? Int ?? 0
        if ![0, 1, 5, 9].contains(priority) {
            return Json.err(
                code: "INVALID_PRIORITY",
                message: "Priority must be one of 0, 1, 5, 9."
            )
        }

        let r = EKReminder(eventStore: Store.shared.store)
        r.calendar = cal
        r.title = title
        if let body = obj["body"] as? String { r.notes = body }
        r.priority = priority

        if let dueStr = obj["dueDate"] as? String, let d = parseDate(dueStr) {
            let comps = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute, .second],
                from: d
            )
            r.dueDateComponents = comps
            let alarm = EKAlarm(absoluteDate: d)
            r.addAlarm(alarm)
        }

        do {
            try Store.shared.store.save(r, commit: true)
        } catch {
            return Json.err(
                code: "SAVE_FAILED",
                message: error.localizedDescription
            )
        }
        return Json.ok(["reminder": reminderDict(r)])
    }

    static func updateReminder(_ payloadJson: String) -> String {
        guard let data = payloadJson.data(using: .utf8),
              let raw = try? JSONSerialization.jsonObject(with: data),
              let obj = raw as? [String: Any]
        else {
            return Json.err(
                code: "INVALID_PAYLOAD",
                message: "Payload must be a JSON object."
            )
        }
        guard let id = obj["id"] as? String else {
            return Json.err(
                code: "INVALID_PAYLOAD",
                message: "Missing required field 'id'."
            )
        }
        guard let r = Store.shared.reminder(id: id) else {
            return Json.err(
                code: "REMINDER_NOT_FOUND",
                message: "No reminder with id '\(id)'."
            )
        }

        if let title = obj["title"] as? String { r.title = title }
        if let body = obj["body"] as? String { r.notes = body }

        if let priority = obj["priority"] as? Int {
            if ![0, 1, 5, 9].contains(priority) {
                return Json.err(
                    code: "INVALID_PRIORITY",
                    message: "Priority must be one of 0, 1, 5, 9."
                )
            }
            r.priority = priority
        }

        let clearDue = (obj["clearDueDate"] as? Bool) ?? false
        if clearDue {
            r.dueDateComponents = nil
            if let alarms = r.alarms {
                for a in alarms { r.removeAlarm(a) }
            }
        } else if let dueStr = obj["dueDate"] as? String,
                  let d = parseDate(dueStr)
        {
            let comps = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute, .second],
                from: d
            )
            r.dueDateComponents = comps
            // Replace existing alarms with a single absolute-date one.
            if let alarms = r.alarms {
                for a in alarms { r.removeAlarm(a) }
            }
            r.addAlarm(EKAlarm(absoluteDate: d))
        }

        do {
            try Store.shared.store.save(r, commit: true)
        } catch {
            return Json.err(
                code: "SAVE_FAILED",
                message: error.localizedDescription
            )
        }
        return Json.ok(["reminder": reminderDict(r)])
    }

    static func completeReminder(_ id: String) -> String {
        guard let r = Store.shared.reminder(id: id) else {
            return Json.err(
                code: "REMINDER_NOT_FOUND",
                message: "No reminder with id '\(id)'."
            )
        }
        r.isCompleted = true
        do {
            try Store.shared.store.save(r, commit: true)
        } catch {
            return Json.err(
                code: "SAVE_FAILED",
                message: error.localizedDescription
            )
        }
        return Json.ok(["reminder": reminderDict(r)])
    }

    static func uncompleteReminder(_ id: String) -> String {
        guard let r = Store.shared.reminder(id: id) else {
            return Json.err(
                code: "REMINDER_NOT_FOUND",
                message: "No reminder with id '\(id)'."
            )
        }
        r.isCompleted = false
        do {
            try Store.shared.store.save(r, commit: true)
        } catch {
            return Json.err(
                code: "SAVE_FAILED",
                message: error.localizedDescription
            )
        }
        return Json.ok(["reminder": reminderDict(r)])
    }

    static func deleteReminder(_ id: String) -> String {
        guard let r = Store.shared.reminder(id: id) else {
            return Json.err(
                code: "REMINDER_NOT_FOUND",
                message: "No reminder with id '\(id)'."
            )
        }
        do {
            try Store.shared.store.remove(r, commit: true)
        } catch {
            return Json.err(
                code: "DELETE_FAILED",
                message: error.localizedDescription
            )
        }
        return Json.ok(["deleted_id": id])
    }
}

// MARK: - Entry point -------------------------------------------------------

func usage() -> String {
    return Json.err(
        code: "USAGE",
        message: "Usage: reminders-eventkit <command> [args]. See source for command list."
    )
}

let args = CommandLine.arguments
if args.count < 2 {
    print(usage())
    exit(1)
}

let cmd = args[1]
let rest = Array(args.dropFirst(2))

// Request permission once up front for all commands. Cached by TCC after
// first grant.
Store.shared.requestAccessOrExit()

let output: String
switch cmd {
case "list-lists":
    output = Command.listLists()

case "get-list-info":
    guard rest.count >= 1 else { print(usage()); exit(1) }
    output = Command.getListInfo(rest[0])

case "list-reminders":
    guard rest.count >= 2 else { print(usage()); exit(1) }
    output = Command.listReminders(rest[0], rest[1])

case "search-reminders":
    guard rest.count >= 3, let limit = Int(rest[2]) else {
        print(usage()); exit(1)
    }
    output = Command.searchReminders(rest[0], rest[1], limit)

case "get-today":
    output = Command.getToday()

case "get-overdue":
    output = Command.getOverdue()

case "get-scheduled":
    output = Command.getScheduled()

case "get-flagged":
    output = Command.getFlagged()

case "get-reminder":
    guard rest.count >= 1 else { print(usage()); exit(1) }
    output = Command.getReminder(rest[0])

case "create-reminder":
    guard rest.count >= 1 else { print(usage()); exit(1) }
    output = Command.createReminder(rest[0])

case "update-reminder":
    guard rest.count >= 1 else { print(usage()); exit(1) }
    output = Command.updateReminder(rest[0])

case "complete-reminder":
    guard rest.count >= 1 else { print(usage()); exit(1) }
    output = Command.completeReminder(rest[0])

case "uncomplete-reminder":
    guard rest.count >= 1 else { print(usage()); exit(1) }
    output = Command.uncompleteReminder(rest[0])

case "delete-reminder":
    guard rest.count >= 1 else { print(usage()); exit(1) }
    output = Command.deleteReminder(rest[0])

default:
    output = Json.err(
        code: "UNKNOWN_COMMAND",
        message: "Unknown command: \(cmd)"
    )
}

print(output)

// Exit 0 on ok, 1 on error, based on the leading status field.
if output.hasPrefix("{\"status\":\"ok\"") {
    exit(0)
} else {
    exit(1)
}
