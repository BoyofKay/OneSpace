# OneSpace Android QA — Invitation UX and App Link fixes (2026-11-19)

Require-Firebase-Config: true
Branch: qa/lifecycle-first-slice-20261119
Scope: QA Android APK and the limited OneSpace invitation landing/App Link association. No Production app or database changes.

Included:
- Change password: Update disabled until current, valid distinct new, and matching confirmation supplied; Cancel alongside Update
- Invite my partner: aligned WhatsApp/SMS and button spacing, confirmation before resending same code to displayed recipient
- Today: remove duplicate generate/revoke CTAs; center Refresh status
- Android verified HTTPS App Link for onespace.live/app-invite
- Website association for QA package onespace.qa with QA APK signing fingerprint, and no-Jekyll support
- Website landing remains install/manual-code fallback, not browser signup; fix broken logo CSP
- Supabase Auth reset: branded HTML template committed, **SMTP sender change awaiting QA Auth custom SMTP configuration** (no unsafe bypass)
- Prior QA archive-retention and read-only separation safety gates remain unchanged

QA tests: run lockfile dependency resolution, Flutter analyze, unit tests, signed QA package and package ID/certificate verification. No publishing to Play or Production.
