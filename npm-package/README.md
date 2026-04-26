# @byte5ai/apple-reminders-mcp

Fast, native MCP server for macOS Apple Reminders via Apple's EventKit framework. 10–200× faster than AppleScript-based alternatives.

```shell
npm install -g @byte5ai/apple-reminders-mcp
```

Then configure your MCP client (Cursor, Zed, etc.) to launch `apple-reminders-mcp` as a stdio MCP server.

## What this package provides

- A thin Node.js stdio MCP server (`server/index.js`)
- A signed, notarized Swift/EventKit binary (downloaded from GitHub Releases during `npm install`, verified against `Developer ID Application: byte5 GmbH`)
- Thirteen MCP tools with safety annotations: list lists, list/search/today/overdue/scheduled/get reminders, and create/update/complete/uncomplete/delete operations.

## Platform

macOS 11+ only. The `os` field in `package.json` is set to `darwin`, so `npm install` on Linux or Windows prints a warning and skips the binary download.

## Distribution alternatives

- **Claude Desktop / Cowork** — use the signed `.mcpb` from [GitHub Releases](https://github.com/byte5ai/apple-reminders-for-claude/releases).
- **Claude Code** — install via the [official plugin directory](https://claude.com/plugins).

See the main [project README](https://github.com/byte5ai/apple-reminders-for-claude#readme) for the full picture.

## Privacy

100% local. No network calls. See [PRIVACY.md](https://github.com/byte5ai/apple-reminders-for-claude/blob/main/PRIVACY.md).

## License

MIT © byte5 GmbH
