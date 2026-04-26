# Privacy Policy — Apple Reminders for Claude

**Effective date:** 2026-04-14
**Publisher:** high5 ventures GmbH, Germany
**Contact:** info@h5ventures.de

## TL;DR

Apple Reminders for Claude is a **local-only** extension. Your reminder data never leaves your Mac. high5 ventures GmbH does not operate any server, does not collect any telemetry, does not log any usage, and has no ability to see or access your reminders, lists, or any derived data.

## Data we collect

**None.** Once installed, the extension performs no network I/O at runtime — no analytics SDK, no telemetry, no crash reporting, no update checks operated by high5 ventures, and no requests to any high5 ventures service.

The npm package's postinstall script downloads the signed Swift binary from `github.com/high5-ventures/apple-reminders-for-claude/releases/...` on first install (and refuses to install if the signature does not chain to `Developer ID Application: high5 ventures GmbH`). That download is anonymous from our side — we do not run a server and have no log of who downloaded what; GitHub may keep its own access logs per its own privacy policy.

## Data the extension accesses locally

To fulfill its function, the extension reads from and writes to your macOS Reminders database through Apple's native **EventKit** framework. This requires your explicit one-time permission via the standard macOS privacy (TCC) prompt the first time the extension is used. You can revoke this access at any time in **System Settings → Privacy & Security → Reminders**.

The accessed data categories are:

- Reminder titles, notes, due dates, priorities, completion state
- Reminder list (calendar) names and identifiers
- Reminder UUIDs assigned by EventKit

All data is read from and written back to your local macOS Reminders database. Nothing is cached, persisted, uploaded, or shared by the extension itself.

## Data sent to Anthropic

When you use this extension inside Claude Desktop, Claude Code, or Claude.ai Cowork, the reminder data returned by our tools is passed into the Claude conversation context so the model can reason about it. That data is then subject to **Anthropic's own privacy policy and terms** — see <https://www.anthropic.com/legal/privacy>.

high5 ventures GmbH has no relationship with, and no visibility into, that data flow. We are a third-party extension publisher; Anthropic operates the Claude product.

## Data sent to Apple

The extension uses Apple's on-device EventKit framework. If you have iCloud sync enabled for Reminders (a setting you control in macOS System Settings), Apple syncs your reminder data across your devices under Apple's own privacy terms — see <https://www.apple.com/legal/privacy>.

## Third parties

high5 ventures GmbH does not share, sell, or disclose any data to third parties. The extension has no third-party dependencies that communicate over the network.

## Data retention

high5 ventures GmbH retains no user data because high5 ventures GmbH receives no user data.

## Children

The extension is general-purpose productivity software and is not directed at children under 16. It does not knowingly collect data from anyone, including children.

## Your rights (GDPR, CCPA, LGPD)

Because high5 ventures GmbH does not process any personal data in connection with this extension, standard data-subject rights (access, rectification, deletion, portability) have no data to act on. If you have concerns about data processed by Anthropic or Apple, please direct requests to those parties using the links above.

If you wish to delete all reminder data on your device, do so through the macOS Reminders app.

## Source code and auditability

This extension is open source under the MIT License. You can audit the complete implementation at <https://github.com/high5-ventures/apple-reminders-for-claude>. Every release is signed with a Developer ID Application certificate issued to high5 ventures GmbH and notarized by Apple.

## Changes

We will update this policy only if the extension's data handling materially changes. Updates are tracked in git history at the URL above and reflected in the `Effective date` at the top of this document.

## Contact

For privacy questions: **info@h5ventures.de**
For bug reports and feature requests: <https://github.com/high5-ventures/apple-reminders-for-claude/issues>
