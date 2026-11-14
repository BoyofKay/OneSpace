# R35 — Connected Occasion Preparation and Reminders

Require-Firebase-Config: true

Previous signed preview: 0.1.410 (phone-tested checklist expansion fix).
Upgrade installed OneSpace on both Android phones without uninstalling,
clearing data, resetting either account, changing the Firebase project,
signing certificate or com.onespace.onespace.preview package ID.

## Included R35 changes
- Occasion preparation timeline is now actionable. Four optional
  reminders: Save money, Research choices, Review ordering deadlines,
  Final preparations. Uses the occasion's configured lead days.
- Each person may explicitly create a reminder with a chosen local
  date/time; never schedule an automatically overdue reminder.
- Private by default, even when the parent occasion is shared. For
  shared occasions, the creator can explicitly send to both partners.
- An active occasion/year/phase reminder cannot be duplicated for the
  same creator; a new year or different person is independent.
- Existing reminders support completion, follow-up notes, snoozing,
  normal server-driven due alerts and unchanged Firebase push.
- Opening the Reminder's related item navigates directly to the original
  Occasion, Calendar event or Checklist instead of a module landing page.
- No new separate notification scheduler or permissions.

## Database and source gates
- Migration 0099 deployed: nullable planning phase and occasion instance
  date plus a creator/year/phase unique index; all old reminder records
  untouched.
- Rollback-only SQL two-account regression 0020: PASS; private occasions
  cannot be exposed by shared reminders, private reminders remain private,
  identical active phase duplicate fails, annual rollover allowed.
- R35 Flutter verification GitHub Actions run 44: SUCCESS,
  commit 3933978d86ea9a8de5a19df7105aeb3eb1a4f98f.
- Acceptance matrix: docs/R35_OCCASION_PREPARATION_REMINDERS_QA.md.

## Mandatory signed release checks
- Flutter locked dependencies, analyzer, entire Flutter test suite.
- Android release APK compiled with required registered Firebase config.
- Verify preview signing certificate and unchanged Android application ID.
- Publish and verify exactly one GitHub release APK.
- Device acceptance remains unconfirmed until both existing accounts
  test reminder creation, private/shared privacy, duplicate prevention
  and deep links.
- Keep checklist crash R34 regression included and no database cleanup.

Controlled R35 preview candidate, November 14 2026.
