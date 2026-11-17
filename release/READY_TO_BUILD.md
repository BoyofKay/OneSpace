# R83 — manually pin places on Our map (QA build)

Require-Firebase-Config: true

QA app (package onespace.qa), QA backend. In-place update over qa-0.1.448.
Production (live.onespace.app) is **not** released by this change.

## Implemented
- **Pin a place** enables a single tap anywhere on the interactive map, or long-press directly.
- Shows a movable-selection result with the exact pinned coordinates and optional OpenStreetMap reverse-lookup label.
- Choose **Been here** or **Add to bucket list** to open the existing full-page place editor, prefilled with the pin's coordinates and available address.
- Saving refreshes existing map pins; cancel/removing the pin leaves stored places untouched.
- Map filters, existing pins, Edit → Find and Google Maps sharing are preserved.
- English and Arabic interface strings included.

## Verification
- Source branch r83-map-pin: **Verify OneSpace iteration** (flutter analyze + flutter test) passed, run 44159377150.
- Manual two-phone tests: docs/R83_QA.md.
- No database migration, permission or production bundle change.

## QA distribution
- GitHub release qa-0.1.<workflow run number> (OneSpace QA); install over the current QA app.
- Do not build/promote the production Play version until this release is accepted on both phones.
