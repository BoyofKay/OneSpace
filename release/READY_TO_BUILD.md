# R31 — Gentle Daily Connection and Today Check-in Lifecycle

Require-Firebase-Config: true

Previous published Android preview: 0.1.407.
Upgrade the existing installation on both phones. NEVER uninstall, clear
app data, recreate accounts, reset pairing or overwrite stored records.

## Included changes
- Daily Connection displays check-in requests by To answer, Sent and History.
- Clearly distinguish Awaiting response, Answered and Expired requests.
- Seven-day expiration on newly sent check-in invitations, server-owned.
- All legacy check-ins (NULL expiration) remain answerable as before.
- Old conversations, responses, recipient privacy and original notices stay intact.
- A pending request can only be answered once by its intended recipient;
  server rejects expired answers, including forged client requests.
- Deep-linked expired requests no longer open the reply editor.
- Reply status labels update while on screen without repeated backend polling.
- Today → Needs Attention no longer offers expired requests as actions.
- Quiet, non-coercive copy. No automatic reminders, resends or extra pushes.
- Existing two-way Firebase gestures and in-app notifications are untouched.

## Backend and source verification
- Migration 0096 deployed: nullable legacy-safe expires_at and new default.
- Migration 0097 deployed: only actionable check-ins in Today attention RPC.
- Rollback-only regression 0017 PASS: default deadline, expiry rejection,
  double-answer protection, old request compatibility and Today filtering.
- Corrected Flutter source analyzer and full tests: PASS on
  commit 648709322fda643b0de4a2ca00bed7137374de2e.
- Subsequent commits affect only test SQL and documentation, not Dart source.
- Two-phone tests described in
  docs/R31_DAILY_CONNECTION_CHECKIN_LIFECYCLE_QA.md.

## Mandatory release gates
- Re-run exact committed Flutter dependencies, analyzer and all tests.
- Compile Android in release mode with required Firebase Android config.
- Verify unchanged com.onespace.onespace.preview application identifier.
- Verify the trusted preview signing certificate, retain signed APK artifact.
- Publish and verify exactly one new GitHub Release asset.
- Do not claim phone-tested until both real Android accounts have passed
  the Daily Connection, Today, Firebase and app-retention acceptance checks.

Controlled R31 candidate, November 14 2026.
