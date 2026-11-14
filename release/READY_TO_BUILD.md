# R30 — Shared Experiences, Trips and Partner Picks

Require-Firebase-Config: true

Release candidate from verified source commit
`ca7d74595ee262d1b9f92370093f7ee49f2294a9`.

Previously published Android preview: `0.1.406`.
Install over the existing signed preview; never uninstall, clear storage,
recreate the two user accounts, reset pairing or destroy partner content.

## Included source changes since R26
- R27: private/shared trip flight quote comparison, alternative itinerary
  options with separate currencies and manual booking confirmation.
- R27: trip-linked travel preparation templates in the existing unified
  To-do and Checklists module, without creating another checklist subsystem.
- R28: date-aware experience ideas and rotating suggestions.
- R29: Shared Experiences realtime partner comments, reviews and schedules,
  conflict-checked saves, timezone-neutral local planned/enjoyed dates and
  category-aware completion buttons for books, movies, TV, games and music.
- R30: Partner Picks. Independent Interested/Maybe/Not now/Clear selection
  by each user; mutual matches, match filter, synchronized live choice panel,
  and prioritization of shared-interest suggestions.
- Existing R25 Firebase FCM delivery remains required. No FCM secret, signing
  identity, package ID or push permissions are changed.

## Backend and security verification
- Existing R27 additive migrations 0093 and 0094 deployed.
- New R30 migration 0095 deployed with RLS and only individual choice update.
- R30 rollback-only SQL regression 0016 passed two-partner access and blocked
  forged edits, with no test data retained. The table is in realtime publication.
- R29 Flutter source verification run 43613481415: SUCCESS.
- R30 Flutter source verification run 43613936191: SUCCESS.
- Documentation and two-phone cases: docs/R29_SHARED_EXPERIENCES_REALTIME_QA.md,
  docs/R30_PARTNER_PICKS_ACCEPTANCE.md.

## GitHub release gates
- Exact committed lockfile, analyzer, all Flutter tests.
- Release-mode Android compilation and Firebase config/package matching.
- Keep `com.onespace.onespace.preview` and the existing trusted preview
  signing certificate, so existing installations can be upgraded in place.
- Publish and verify exactly one signed preview release artifact.
- The new features are not marked physical-device-tested until each partner
  verifies realtime collaboration, private/shared permissions, checklist and
  trip workflows, and FCM pushes on their own phone.

One controlled R30 build from already verified source, November 14, 2026.
