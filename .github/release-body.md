## Apple Reminders for Claude

Fast, native Apple Reminders access for Claude — signed with `Developer ID Application: byte5 GmbH` and notarized by Apple.

### Install

| Target | How |
|---|---|
| **Claude Desktop / Cowork** | Download `apple-reminders.mcpb` below and double-click, or install from the Anthropic Extensions Directory. |
| **Claude Code CLI** | `/plugin install apple-reminders@claude-plugins-official` |
| **Any MCP client (Cursor, Zed, …)** | `npm install -g @byte5ai/apple-reminders-mcp` |

### Verify signature

```shell
codesign --verify --verbose reminders-eventkit
spctl --assess --type execute reminders-eventkit
```

Expected signer: `Developer ID Application: byte5 GmbH`.

See [CHANGELOG.md](https://github.com/byte5ai/apple-reminders-for-claude/blob/main/CHANGELOG.md) for what changed.
