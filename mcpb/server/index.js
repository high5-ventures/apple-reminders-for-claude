#!/usr/bin/env node

// Copyright (c) 2026 byte5 GmbH
// SPDX-License-Identifier: MIT
//
// apple-reminders MCP server — thin stdio wrapper around the bundled
// Swift/EventKit binary (bin/reminders-eventkit). One tool call = one
// spawn of the binary with positional or JSON-payload arguments. All
// reading, parsing, and schema work lives in Swift; Node only translates.

import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
} from "@modelcontextprotocol/sdk/types.js";
import { execFile } from "child_process";
import { promisify } from "util";

const execFileAsync = promisify(execFile);

const BINARY = process.env.REMINDERS_BINARY;
if (!BINARY) {
  console.error("REMINDERS_BINARY env var is not set");
  process.exit(1);
}

// ---------------------------------------------------------------------------
// Binary invocation
// ---------------------------------------------------------------------------

/**
 * Run the Swift binary with the given argv. Always returns the parsed JSON
 * envelope ({status, data|code|message}). Never throws on binary errors —
 * the envelope carries them through to the caller so the MCP layer can
 * decide how to surface them.
 *
 * Throws only if the binary itself crashes, is missing, or emits non-JSON.
 */
// Hard ceiling on a single binary invocation. The Swift binary is designed
// to return in well under a second on databases with hundreds of reminders,
// so anything approaching this value almost certainly means the macOS TCC
// permission prompt is waiting for the user (first run only) or EventKit is
// wedged. 30 s keeps us well inside the MCP client's own request timeout
// while giving first-run users time to click "Allow".
const BINARY_TIMEOUT_MS = 30_000;

async function runBinary(args, { stdin } = {}) {
  let stdout = "";
  let stderr = "";
  let exitCode = 0;
  let killed = false;
  let signal = null;
  try {
    const child = execFileAsync(BINARY, args, {
      maxBuffer: 16 * 1024 * 1024, // 16 MB — plenty for large reminder lists
      timeout: BINARY_TIMEOUT_MS,
      killSignal: "SIGTERM",
    });
    if (typeof stdin === "string") {
      child.child.stdin.end(stdin);
    }
    const result = await child;
    stdout = result.stdout;
    stderr = result.stderr;
  } catch (err) {
    // execFile throws on non-zero exit, on timeout, and on signal. The binary
    // uses exit 1 for logical errors and still emits a JSON envelope on
    // stdout — salvage it when possible.
    stdout = err.stdout || "";
    stderr = err.stderr || "";
    exitCode = typeof err.code === "number" ? err.code : 1;
    killed = err.killed === true;
    signal = err.signal || null;

    // Timeout: Node kills the child with SIGTERM and sets `killed: true`.
    if (killed && signal === "SIGTERM") {
      throw new Error(
        `Reminders binary timed out after ${BINARY_TIMEOUT_MS} ms. ` +
          `If this is the first invocation, macOS may be waiting for you to ` +
          `grant Reminders access in the privacy prompt — click "Allow" and ` +
          `retry. Otherwise, EventKit may be wedged; try again in a moment.`
      );
    }
    if (!stdout) {
      throw new Error(
        `Binary crashed (exit ${exitCode}${signal ? `, signal ${signal}` : ""}): ${stderr || err.message}`
      );
    }
  }

  const line = stdout.trim();
  if (!line) {
    throw new Error(
      `Binary produced no output (exit ${exitCode}, stderr: ${stderr})`
    );
  }
  try {
    return JSON.parse(line);
  } catch (_parseErr) {
    throw new Error(
      `Binary produced non-JSON output: ${line.slice(0, 500)}`
    );
  }
}

/**
 * Wrap a binary envelope as an MCP tool result. The envelope is always
 * returned verbatim as JSON text — downstream tools and the LLM see the
 * exact same schema that the skill's Bash path returns.
 */
function envelopeToMcpResult(envelope) {
  const text = JSON.stringify(envelope, null, 2);
  const isError = envelope.status === "error";
  return {
    content: [{ type: "text", text }],
    ...(isError ? { isError: true } : {}),
  };
}

// ---------------------------------------------------------------------------
// Tool definitions
// ---------------------------------------------------------------------------

const TOOLS = [
  {
    name: "get_lists",
    description:
      "List all reminder lists on this Mac with open and completed counts. No arguments.",
    inputSchema: { type: "object", properties: {} },
  },
  {
    name: "get_list_info",
    description: "Get metadata for one reminder list by exact name.",
    inputSchema: {
      type: "object",
      properties: {
        list: {
          type: "string",
          description: "Exact name of the list, e.g. 'Groceries'",
        },
      },
      required: ["list"],
    },
  },
  {
    name: "list_reminders",
    description:
      "List reminders in a specific list. Filter must be one of: open, completed, all.",
    inputSchema: {
      type: "object",
      properties: {
        list: {
          type: "string",
          description: "Exact name of the list",
        },
        filter: {
          type: "string",
          enum: ["open", "completed", "all"],
          default: "open",
          description: "Which reminders to include (default: open)",
        },
      },
      required: ["list"],
    },
  },
  {
    name: "search_reminders",
    description:
      "Full-text search across all reminder lists. Matches against title and notes. Case-insensitive.",
    inputSchema: {
      type: "object",
      properties: {
        query: {
          type: "string",
          description: "Search query, matched against title and notes",
        },
        filter: {
          type: "string",
          enum: ["open", "completed", "all"],
          default: "open",
          description: "Which reminders to include (default: open)",
        },
        limit: {
          type: "integer",
          minimum: 0,
          default: 0,
          description: "Max results; 0 = unlimited (default: 0)",
        },
      },
      required: ["query"],
    },
  },
  {
    name: "get_today",
    description:
      "Get all open reminders due today (local time) across every list.",
    inputSchema: { type: "object", properties: {} },
  },
  {
    name: "get_overdue",
    description:
      "Get all open reminders whose due date is strictly before today.",
    inputSchema: { type: "object", properties: {} },
  },
  {
    name: "get_scheduled",
    description:
      "Get all open reminders that have any due date (today, future, or past).",
    inputSchema: { type: "object", properties: {} },
  },
  {
    name: "get_reminder",
    description: "Fetch a single reminder by its stable EventKit UUID.",
    inputSchema: {
      type: "object",
      properties: {
        id: {
          type: "string",
          description: "The reminder's EventKit UUID",
        },
      },
      required: ["id"],
    },
  },
  {
    name: "create_reminder",
    description:
      "Create a new reminder in a specified list. Due date must be ISO-8601 local time (e.g. 2026-04-11T18:00:00) or omitted. Priority is 0 (none), 1 (high), 5 (medium), or 9 (low). The `flagged` field is accepted for API stability but silently ignored — EventKit does not expose it.",
    inputSchema: {
      type: "object",
      properties: {
        list: {
          type: "string",
          description: "Target list name (must already exist)",
        },
        title: { type: "string", description: "Reminder title" },
        body: {
          type: "string",
          description: "Optional notes/body text",
        },
        dueDate: {
          type: "string",
          description:
            "Optional ISO-8601 local-time due date, e.g. 2026-04-11T18:00:00",
        },
        priority: {
          type: "integer",
          enum: [0, 1, 5, 9],
          default: 0,
          description: "0=none, 1=high, 5=medium, 9=low",
        },
      },
      required: ["list", "title"],
    },
  },
  {
    name: "update_reminder",
    description:
      "Update an existing reminder by ID. Only provided fields are changed. Use `clearDueDate: true` to explicitly remove a due date (different from omitting `dueDate`). The `flagged` field is accepted but silently ignored.",
    inputSchema: {
      type: "object",
      properties: {
        id: { type: "string", description: "EventKit UUID of the reminder" },
        title: { type: "string" },
        body: { type: "string" },
        dueDate: {
          type: "string",
          description: "New ISO-8601 local-time due date",
        },
        clearDueDate: {
          type: "boolean",
          description: "If true, explicitly remove the existing due date",
        },
        priority: { type: "integer", enum: [0, 1, 5, 9] },
      },
      required: ["id"],
    },
  },
  {
    name: "complete_reminder",
    description: "Mark a reminder as completed by ID.",
    inputSchema: {
      type: "object",
      properties: {
        id: { type: "string" },
      },
      required: ["id"],
    },
  },
  {
    name: "uncomplete_reminder",
    description: "Unmark a completed reminder (set it back to open).",
    inputSchema: {
      type: "object",
      properties: {
        id: { type: "string" },
      },
      required: ["id"],
    },
  },
  {
    name: "delete_reminder",
    description: "Permanently delete a reminder by ID.",
    inputSchema: {
      type: "object",
      properties: {
        id: { type: "string" },
      },
      required: ["id"],
    },
  },
];

// ---------------------------------------------------------------------------
// MCP server
// ---------------------------------------------------------------------------

const server = new Server(
  { name: "apple-reminders", version: "0.1.1" },
  { capabilities: { tools: {} } }
);

server.setRequestHandler(ListToolsRequestSchema, async () => ({
  tools: TOOLS,
}));

server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const toolName = request.params.name;
  const args = request.params.arguments || {};

  // Translate each tool call into the corresponding binary invocation.
  // Scalar commands pass positional args; create/update pass a JSON payload.
  try {
    switch (toolName) {
      case "get_lists":
        return envelopeToMcpResult(await runBinary(["list-lists"]));

      case "get_list_info":
        requireString(args, "list");
        return envelopeToMcpResult(
          await runBinary(["get-list-info", args.list])
        );

      case "list_reminders": {
        requireString(args, "list");
        const filter = args.filter || "open";
        return envelopeToMcpResult(
          await runBinary(["list-reminders", args.list, filter])
        );
      }

      case "search_reminders": {
        requireString(args, "query");
        const filter = args.filter || "open";
        const limit = String(args.limit ?? 0);
        return envelopeToMcpResult(
          await runBinary(["search-reminders", args.query, filter, limit])
        );
      }

      case "get_today":
        return envelopeToMcpResult(await runBinary(["get-today"]));

      case "get_overdue":
        return envelopeToMcpResult(await runBinary(["get-overdue"]));

      case "get_scheduled":
        return envelopeToMcpResult(await runBinary(["get-scheduled"]));

      case "get_reminder":
        requireString(args, "id");
        return envelopeToMcpResult(
          await runBinary(["get-reminder", args.id])
        );

      case "create_reminder": {
        requireString(args, "list");
        requireString(args, "title");
        const payload = {
          list: args.list,
          title: args.title,
        };
        if (typeof args.body === "string") payload.body = args.body;
        if (typeof args.dueDate === "string") payload.dueDate = args.dueDate;
        if (typeof args.priority === "number") payload.priority = args.priority;
        // Pass the JSON payload over stdin so user content never appears on
        // the command line. The Swift binary reads stdin when it sees `-`.
        return envelopeToMcpResult(
          await runBinary(["create-reminder", "-"], {
            stdin: JSON.stringify(payload),
          })
        );
      }

      case "update_reminder": {
        requireString(args, "id");
        const payload = { id: args.id };
        if (typeof args.title === "string") payload.title = args.title;
        if (typeof args.body === "string") payload.body = args.body;
        if (typeof args.dueDate === "string") payload.dueDate = args.dueDate;
        if (args.clearDueDate === true) payload.clearDueDate = true;
        if (typeof args.priority === "number") payload.priority = args.priority;
        return envelopeToMcpResult(
          await runBinary(["update-reminder", "-"], {
            stdin: JSON.stringify(payload),
          })
        );
      }

      case "complete_reminder":
        requireString(args, "id");
        return envelopeToMcpResult(
          await runBinary(["complete-reminder", args.id])
        );

      case "uncomplete_reminder":
        requireString(args, "id");
        return envelopeToMcpResult(
          await runBinary(["uncomplete-reminder", args.id])
        );

      case "delete_reminder":
        requireString(args, "id");
        return envelopeToMcpResult(
          await runBinary(["delete-reminder", args.id])
        );

      default:
        return {
          content: [{ type: "text", text: `Unknown tool: ${toolName}` }],
          isError: true,
        };
    }
  } catch (err) {
    return {
      content: [
        {
          type: "text",
          text: `Tool error: ${err instanceof Error ? err.message : String(err)}`,
        },
      ],
      isError: true,
    };
  }
});

function requireString(args, key) {
  if (typeof args[key] !== "string" || args[key].length === 0) {
    throw new Error(`Missing required argument: ${key}`);
  }
}

async function main() {
  const transport = new StdioServerTransport();
  await server.connect(transport);
}

main().catch((err) => {
  console.error("Server fatal error:", err);
  process.exit(1);
});
