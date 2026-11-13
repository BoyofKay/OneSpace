# OneSpace — single consolidated private Android preview, R12–R17

**NOT A RELEASE TRIGGER.** This document does not build an APK. Keep `release/READY_TO_BUILD.md` unchanged.

## Consolidated scope
- R12: saved contacts, check-ins, richer gesture preferences and letters.
- R13: Shared Experiences, partner ratings and conversations.
- R14: Trips & Journeys, collaborative itinerary and countdowns.
- R15: secure PDF/image travel documents.
- R16: Android Share into Coordinate, shopping option comparisons, occasion preparation/budgets, selfies and photo layouts.
- R17: four Material 3 palettes, device Light/Dark/System selection, quiet seasonal overlays, responsive phone/tablet navigation, regional holiday overlays, birthdays, anniversaries and personal special dates linked to the shared calendar.

## Release staging
The Flutter source and additive Supabase migrations through `0071_r17_occasion_honoree.sql` have been committed/applied. Existing auth users, memberships, shared space and other records must remain untouched.

Before releasing, run **one consolidated** Flutter dependency resolution, analysis, tests, Android compile and signed APK build when GitHub quota is available and the user authorizes it. Fix compile/test defects in source before another build. An APK may only be called ready after actual install/upgrade testing on both Android devices.

Ensure the release workflow always keeps the signed APK in GitHub Actions Artifacts if GitHub Releases denies publishing with HTTP 403. Do not repeat release attempts just to address a token-permission failure.

## Acceptance references
- [R12–R16 consolidated cases](../docs/CONSOLIDATED_PREVIEW_R12_R16_QA.md)
- [R17 visual, accessibility and holiday calendar cases](../docs/R17_MODERN_DESIGN_AND_HOLIDAY_CALENDAR_QA.md)

## Known deferred work
OS-level push/alarm guarantees, bidirectional Google/Apple calendar sync, iOS native share sheet extension, fully translated secondary UI, external provider rate/terms validation for public launch, production performance profiling and screen reader acceptance. Regional holidays are informative overlays; don't treat tentative lunar dates or bank-specific observed days as confirmed universal closures.

## Source verification already done
Checked new Dart delimiter structure and local relative imports, the new RLS policies and existing data counts. This is not equivalent to `flutter analyze`, `flutter test`, signed APK verification or physical two-device acceptance.
