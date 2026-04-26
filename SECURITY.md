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
- The Node.js MCP wrapper (`npm-package/server/index.js`)
- The Claude Code skill (`skills/apple-reminders/`)
- The npm package install scripts (`npm-package/scripts/install-binary.js`, `scripts/install-binary.sh`)
- The release and signing pipeline in `.github/workflows/`

Out of scope:

- Bugs in Apple's EventKit framework itself
- Bugs in Anthropic's Claude clients
- Issues requiring physical access to an unlocked, attended Mac

## Security-relevant design choices

- **Local-only at runtime:** Once installed, the extension performs no network I/O. Any observed outbound runtime traffic is a bug. The npm postinstall and the Claude Code plugin SessionStart hook do download the signed Swift binary from GitHub Releases on first install (and refuse to run if the signature does not chain to `Developer ID Application: high5 ventures GmbH`); after that, the binary stays local.
- **Signature re-verification on every start:** Both installers re-run `codesign --verify` against the cached binary on each invocation, not just at first install, so a tampered cached file is detected and replaced.
- **stdin for payloads:** User content is passed to the Swift binary via stdin, never through shell arguments, to eliminate injection from untrusted LLM-generated strings.
- **Pre-TCC validation:** Filter values, integer parameters, and JSON payload shape are validated before the macOS TCC permission prompt is requested, so malformed calls do not leave a ghost permission dialog.
- **TCC permission:** All reminder access is gated by macOS's standard privacy prompt. The user must grant access once and can revoke it at any time.
- **Signed + notarized binary:** Every release binary is signed with `Developer ID Application: high5 ventures GmbH` and the binary itself is notarized. The `.mcpb` bundle as a whole is also notarized (Apple's notary service `Accepted` it server-side); offline stapling is not available for `.mcpb` because Apple's `stapler` does not support that bundle format, so Gatekeeper resolves the notarization ticket online on first launch. Verify with `codesign --verify --verbose $BINARY` and `spctl --assess --type execute $BINARY`.
- **Hardened Runtime:** The binary ships with Hardened Runtime enabled and all relaxation flags (`allow-jit`, `allow-unsigned-executable-memory`, `allow-dyld-environment-variables`, `disable-library-validation`, `disable-executable-page-protection`) explicitly disabled.
- **Pinned CI supply chain:** All third-party GitHub Actions are pinned by commit SHA; `mcp-publisher` is pinned to a tagged version and verified against a known-good SHA-256 hash before execution. Apple credentials are scoped to the specific notarization step rather than the entire job.
- **Reproducible builds:** `npm-package/package-lock.json` and `mcpb/package-lock.json` are committed; the release pipeline uses pinned dependency installs.

## Disclosure

Once a fix is released, we publish a CVE-style advisory in the GitHub repository's Security Advisories tab, crediting the reporter unless they request anonymity.
