# Security Policy

## Supported versions

We apply security fixes only to the latest minor release line. If you are running an older version, please upgrade before filing a vulnerability report.

| Version | Supported |
|---------|-----------|
| 1.0.x   | ✅        |
| < 1.0   | ❌        |

## Reporting a vulnerability

**Please do not report security vulnerabilities through public GitHub issues.**

Instead, report them privately to **info@h5ventures.de** with the subject line `[security] apple-reminders-for-claude`.

Include, where possible:

- Affected version and macOS version
- A minimal reproduction
- The impact you observed or believe possible
- Any suggested mitigation

We aim to acknowledge reports within **3 working days** and to ship a fix or a concrete remediation plan within **30 days** of a confirmed report.

## Scope

In scope:

- The bundled Swift/EventKit binary (`src/reminders-eventkit.swift`)
- The Node.js MCP wrapper (`mcpb/server/index.js`)
- The Claude Code skill (`skill/`)
- The release and signing pipeline in `.github/workflows/`

Out of scope:

- Bugs in Apple's EventKit framework itself
- Bugs in Anthropic's Claude clients
- Issues requiring physical access to an unlocked, attended Mac

## Security-relevant design choices

- **Local-only:** The extension performs no network I/O. Any observed outbound traffic is a bug.
- **stdin for payloads:** User content is passed to the Swift binary via stdin, never through shell arguments, to eliminate injection from untrusted LLM-generated strings.
- **TCC permission:** All reminder access is gated by macOS's standard privacy prompt. The user must grant access once and can revoke it at any time.
- **Signed + notarized binary:** Every release binary is signed with `Developer ID Application: high5 ventures GmbH` and stapled by Apple's notary service. Verify with `codesign --verify --verbose $BINARY` and `spctl --assess --type execute $BINARY`.
- **Hardened Runtime:** The binary ships with Hardened Runtime enabled. Only EventKit-related entitlements are declared.
- **Reproducible builds:** `mcpb/package-lock.json` is committed; `build.sh` uses `npm ci` to eliminate resolver drift.

## Disclosure

Once a fix is released, we publish a CVE-style advisory in the GitHub repository's Security Advisories tab, crediting the reporter unless they request anonymity.
