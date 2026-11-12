// Copyright (c) 2026 high5 ventures GmbH
// SPDX-License-Identifier: MIT
//
// CI helper for eventkit-integration.mjs: a fresh Reminders store has no list,
// and reminders-eventkit cannot create one. Creates a local list named after
// the first argument through EventKit, without the Reminders app. Needs
// Reminders access like the binary itself; build.yml grants it by path.
//
//   swiftc make-reminder-list.swift -o make-reminder-list \
//     -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker ../src/Info.plist
//   ./make-reminder-list CI

import EventKit
import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

// As in reminders-eventkit: re-exec with TCC responsibility disclaimed, so
// tccd checks this executable's grant instead of the runner's.
if ProcessInfo.processInfo.environment["MAKE_REMINDER_LIST_DISCLAIMED"] == nil,
   let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "responsibility_spawnattrs_setdisclaim") {
    typealias SetDisclaim = @convention(c) (UnsafeMutablePointer<posix_spawnattr_t?>, Int32) -> Int32
    var path = [CChar](repeating: 0, count: Int(PATH_MAX))
    var size = UInt32(path.count)
    var attributes: posix_spawnattr_t?
    if _NSGetExecutablePath(&path, &size) == 0, posix_spawnattr_init(&attributes) == 0,
       posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETEXEC)) == 0,
       unsafeBitCast(symbol, to: SetDisclaim.self)(&attributes, 1) == 0 {
        setenv("MAKE_REMINDER_LIST_DISCLAIMED", "1", 1)
        posix_spawn(nil, path, nil, &attributes, CommandLine.unsafeArgv, environ)
        fail("re-exec failed")
    }
}

let name = CommandLine.arguments.dropFirst().first ?? "CI"
let store = EKEventStore()

let granted = DispatchSemaphore(value: 0)
var ok = false
let done: (Bool, Error?) -> Void = { result, _ in ok = result; granted.signal() }
if #available(macOS 14.0, *) {
    store.requestFullAccessToReminders(completion: done)
} else {
    store.requestAccess(to: .reminder, completion: done)
}
if granted.wait(timeout: .now() + 30) == .timedOut || !ok {
    fail("no Reminders access")
}

let sources = store.sources
for s in sources {
    print("source: \(s.title) type=\(s.sourceType.rawValue) reminder lists=\(s.calendars(for: .reminder).count)")
}
guard let source = store.defaultCalendarForNewReminders()?.source
    ?? sources.first(where: { $0.sourceType == .local })
    ?? sources.first
else {
    fail("the store has no source to create a list in")
}

let list = EKCalendar(for: .reminder, eventStore: store)
list.title = name
list.source = source
do {
    try store.saveCalendar(list, commit: true)
} catch {
    fail("could not create the list in \(source.title): \(error.localizedDescription)")
}
print("created list \(name) (\(list.calendarIdentifier)) in \(source.title)")
