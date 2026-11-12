// Copyright (c) 2026 high5 ventures GmbH
// SPDX-License-Identifier: MIT
//
// Drives the MCP server and the real binary against a real Reminders store:
// every call goes through EventKit and is read back from the store by a fresh
// process. Needs Reminders access for the binary and at least one list;
// build.yml grants the access on a CI VM, whose store has the default list.
//
//   REMINDERS_BINARY=$PWD/../dist/reminders-eventkit node test/eventkit-integration.mjs
//
// It creates reminders whose titles start with a unique prefix and deletes
// them again at the end. Not part of the npm package (see `files`).

import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";
import { isDeepStrictEqual, inspect } from "node:util";

const client = new Client({ name: "eventkit-integration", version: "0" });
await client.connect(
  new StdioClientTransport({
    command: process.execPath,
    args: ["server/index.js"],
    env: { ...process.env },
  })
);

async function call(name, args = {}) {
  const result = await client.callTool({ name, arguments: args });
  return JSON.parse(result.content[0].text);
}

let failures = 0;
function check(ok, what, detail) {
  console.log(`${ok ? "PASS" : "FAIL"}  ${what}`);
  if (!ok) {
    failures += 1;
    if (detail !== undefined) console.log(`      ${inspect(detail, { depth: 6 })}`);
  }
}
function okData(envelope, what) {
  check(envelope.status === "ok", what, envelope);
  return envelope.status === "ok" ? envelope.data : null;
}
function same(actual, expected, what) {
  check(isDeepStrictEqual(actual, expected), what, { actual, expected });
}
function invalid(envelope, what) {
  check(
    envelope.status === "error" && envelope.code === "INVALID_PAYLOAD",
    what,
    envelope
  );
}

// Local calendar dates, as the binary reads them.
function day(offset) {
  const d = new Date();
  d.setDate(d.getDate() + offset);
  const pad = (n) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
}
const tomorrow = day(1);
const inAMonth = day(30);

const lists = okData(await call("get_lists"), "get_lists");
if (!lists || lists.lists.length === 0) {
  console.log("FAIL  no reminder list to write into");
  process.exit(1);
}
const list = `id:${lists.lists[0].calendar_identifier}`;
const prefix = `ci-${process.pid}-${Date.now()}`;
let seq = 0;
const title = (what) => `${prefix} ${++seq} ${what}`;

async function mine() {
  const data = await call("search_reminders", { query: prefix, filter: "all" });
  return data.status === "ok" ? data.data.reminders : [];
}

async function created(args, what) {
  const data = okData(
    await call("create_reminder", { list, title: title(what), ...args }),
    `create: ${what}`
  );
  return data ? data.reminder : null;
}

async function stored(id) {
  const data = await call("get_reminder", { id });
  return data.status === "ok" ? data.data.reminder : data;
}

// --- Create: the rule is saved and read back unchanged --------------------

const roundTrips = [
  [
    "every other week on Monday and Thursday, five times",
    { dueDate: `${tomorrow}T09:00:00` },
    { frequency: "weekly", interval: 2, daysOfWeek: ["monday", "thursday"], end: { count: 5 } },
    null,
  ],
  [
    "last day of every month until a date, without a due time",
    { dueDate: tomorrow },
    { frequency: "monthly", daysOfMonth: [-1], end: { date: inAMonth } },
    { frequency: "monthly", interval: 1, daysOfMonth: [-1], end: { date: `${inAMonth}T23:59:59` } },
  ],
  [
    "last Friday of every month",
    { dueDate: `${tomorrow}T18:30:00` },
    { frequency: "monthly", daysOfWeek: [{ day: "friday", week: -1 }] },
    { frequency: "monthly", interval: 1, daysOfWeek: [{ day: "friday", week: -1 }] },
  ],
  [
    "first Monday of March and September",
    { dueDate: tomorrow },
    { frequency: "yearly", monthsOfYear: [3, 9], daysOfWeek: [{ day: "monday", week: 1 }] },
    { frequency: "yearly", interval: 1, monthsOfYear: [3, 9], daysOfWeek: [{ day: "monday", week: 1 }] },
  ],
  [
    "last weekday of every month",
    { dueDate: tomorrow },
    {
      frequency: "monthly",
      daysOfWeek: ["monday", "tuesday", "wednesday", "thursday", "friday"],
      setPositions: [-1],
    },
    {
      frequency: "monthly",
      interval: 1,
      daysOfWeek: ["monday", "tuesday", "wednesday", "thursday", "friday"],
      setPositions: [-1],
    },
  ],
];

for (const [what, args, rule, expectedRule] of roundTrips) {
  const expected = expectedRule ?? rule;
  const r = await created({ ...args, recurrence: rule }, what);
  if (!r) continue;
  same(r.recurrence, expected, `create returns the rule: ${what}`);
  same((await stored(r.id)).recurrence, expected, `the store keeps the rule: ${what}`);
}

const plain = await created({ dueDate: `${tomorrow}T09:00:00` }, "not repeating");
if (plain) same((await stored(plain.id)).recurrence, null, "a reminder that does not repeat reads recurrence null");

// --- Create: invalid rules are refused and nothing is saved ---------------

const refused = [
  ["no due date", {}, { frequency: "daily" }],
  ["unknown frequency", { dueDate: tomorrow }, { frequency: "hourly" }],
  ["interval 0", { dueDate: tomorrow }, { frequency: "daily", interval: 0 }],
  ["days of the month on a weekly rule", { dueDate: tomorrow }, { frequency: "weekly", daysOfMonth: [1] }],
  ["nth weekday on a weekly rule", { dueDate: tomorrow }, { frequency: "weekly", daysOfWeek: [{ day: "monday", week: 1 }] }],
  ["unknown field", { dueDate: tomorrow }, { frequency: "weekly", byDay: ["MO"] }],
  ["set position alone", { dueDate: tomorrow }, { frequency: "monthly", setPositions: [-1] }],
  ["end with date and count", { dueDate: tomorrow }, { frequency: "daily", end: { date: inAMonth, count: 3 } }],
];
const before = (await mine()).length;
for (const [what, args, rule] of refused) {
  invalid(
    await call("create_reminder", { list, title: title(what), ...args, recurrence: rule }),
    `create refuses: ${what}`
  );
}
same((await mine()).length, before, "refused creates saved nothing");

// --- Update ----------------------------------------------------------------

const u = await created({ dueDate: `${tomorrow}T09:00:00` }, "update target");
if (u) {
  let data = okData(
    await call("update_reminder", { id: u.id, recurrence: { frequency: "daily" } }),
    "update adds a rule"
  );
  same(data?.reminder.recurrence, { frequency: "daily", interval: 1 }, "update returns the added rule");
  same((await stored(u.id)).recurrence, { frequency: "daily", interval: 1 }, "the store keeps the added rule");

  okData(await call("update_reminder", { id: u.id, title: title("renamed") }), "update the title only");
  same((await stored(u.id)).recurrence, { frequency: "daily", interval: 1 }, "an update without recurrence keeps the rule");

  const weekdays = { frequency: "weekly", daysOfWeek: ["monday", "tuesday", "wednesday", "thursday", "friday"] };
  okData(await call("update_reminder", { id: u.id, recurrence: weekdays }), "update replaces the rule");
  same((await stored(u.id)).recurrence, { ...weekdays, interval: 1 }, "the store keeps the replaced rule");

  invalid(
    await call("update_reminder", { id: u.id, clearDueDate: true }),
    "update refuses to remove the due date of a repeating reminder alone"
  );
  const kept = await stored(u.id);
  check(kept.due_date === `${tomorrow}T09:00:00` && kept.recurrence !== null, "the refused update changed nothing", kept);

  invalid(
    await call("update_reminder", { id: u.id, recurrence: { frequency: "daily" }, clearRecurrence: true }),
    "update refuses recurrence together with clearRecurrence"
  );

  okData(await call("update_reminder", { id: u.id, clearDueDate: true, clearRecurrence: true }), "update removes due date and rule together");
  const cleared = await stored(u.id);
  check(cleared.due_date === null && cleared.recurrence === null, "due date and rule are gone", cleared);
}

// --- Completing a repeating reminder ---------------------------------------
// The reminder moves on to its next occurrence and stays open under the same
// id; EventKit keeps the finished occurrence as a separate completed copy.

const c = await created(
  { dueDate: `${tomorrow}T09:00:00`, recurrence: { frequency: "daily" } },
  "complete daily"
);
if (c) {
  const done = okData(await call("complete_reminder", { id: c.id }), "complete a repeating reminder");
  const next = { id: c.id, completed: false, due_date: `${day(2)}T09:00:00`, recurrence: { frequency: "daily", interval: 1 } };
  const pick = (r) => r && { id: r.id, completed: r.completed, due_date: r.due_date, recurrence: r.recurrence };
  same(pick(done?.reminder), next, "completing returns the next occurrence, still open");
  same(pick(await stored(c.id)), next, "the store keeps the reminder open at its next occurrence");
  const copies = (await mine()).filter((r) => r.name === c.name && r.id !== c.id);
  same(
    copies.map((r) => ({ completed: r.completed, due_date: r.due_date, recurrence: r.recurrence })),
    [{ completed: true, due_date: `${tomorrow}T09:00:00`, recurrence: null }],
    "the finished occurrence is kept as a completed copy without the rule"
  );
}

// --- Clean up ---------------------------------------------------------------

for (const r of await mine()) {
  await call("delete_reminder", { id: r.id });
}
same((await mine()).length, 0, "cleanup deleted every test reminder");

await client.close();
console.log(failures === 0 ? "all checks passed" : `${failures} check(s) failed`);
process.exit(failures === 0 ? 0 : 1);
