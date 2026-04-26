## Apple Reminders for Claude

Fast, native Apple Reminders access for Claude — signed with `Developer ID Application: high5 ventures GmbH` and notarized by Apple.

### Install

| Target | How |
|---|---|
| **Claude Desktop / Cowork** | Download `apple-reminders.mcpb` below and double-click, or install from the Anthropic Extensions Directory. |
| **Claude Code CLI** | `/plugin install apple-reminders@claude-plugins-official` |
| **Any MCP client (Cursor, Zed, …)** | `npm install -g @high5ventures/apple-reminders-mcp` |

### Verify signature

```shell
codesign --verify --verbose reminders-eventkit
spctl --assess --type execute reminders-eventkit
```

Expected signer: `Developer ID Application: high5 ventures GmbH`.

See [CHANGELOG.md](https://github.com/high5-ventures/apple-reminders-for-claude/blob/main/CHANGELOG.md) for what changed.
