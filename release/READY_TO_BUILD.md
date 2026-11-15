# R59 — Your data and account

Require-Firebase-Config: true

Previous signed preview: 0.1.425 (R58).
Preserve the existing com.onespace.onespace.preview Android package,
same signing certificate, Firebase config, biometrics, all account and
partner pairing data, checklists, notes, memories and user documents.
INSTALL AS AN IN-PLACE UPDATE only. Never uninstall or clear data.

## Included since 0.1.425
- Settings › Privacy › Your data and account: Download my data (JSON to
  Downloads/OneSpace) and Delete my account (7-day grace; shared items stay
  for the partner; private data removed). Keep-my-account prompt at sign-in.

## Database
- Applied live before this build: 0117 r59 account data (deletion requests,
  export_my_data, purge functions, daily cron). Edge Function
  onespace-account-purge v1 deployed and smoke-tested (processed 0).

## Verification
- "Verify OneSpace iteration" passed on r59-account-data.

## Two-phone validation
Follow docs/R59_QA.md.

Controlled R59 signed preview candidate, November 15, 2026.
