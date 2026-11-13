# R13 verify only — Shared Experiences

The new experience catalog is additive and does not overwrite existing data.

Validate:
- Suggest, edit, archive/restore shared movies, TV shows, music, books, games, other.
- Search by title/details; filter categories and suggested/planned/enjoyed.
- Save optional source URL and platform; open original source externally.
- Each partner writes only their own rating/review and sees both.
- Each partner comments; only their own comment can be retracted.
- Audit history for edited entries.
- Notifications for new suggestions and discussion with deep link.
- Both Android phones, two accounts, privacy and membership.
- Existing accounts, pairing, Activities, Notes, Calendar and contacts unchanged.

Only after automated validation should the release marker be updated once for a consolidated APK.

Validation invocation: analyzer + automated Flutter tests, no APK.

Validation pass 2: use the corrected nullable platform rendering.

Validation pass 3: planned Shared Experiences in Today and deep-link destination; additive SQL 0062 deployed.

## Consolidated R12–R17 quality gate, November 13, 2026

Run once as an independent verification **without generating an APK**. Validate the exact lockfile, Flutter analyzer, and all Flutter tests against commit 2471a88a77e1543e111036e8a66c80ce56a446f3. Resolve any failures before updating the release-trigger marker. Do not delete users, memberships, or content.

## Compile-error corrections verification

Retest consolidated R12–R17 after replacing the invalid travel-document TextField controller with a TextFormField initial value and removing the unavailable Cupertino transition symbol. This is **verify only**, without APK or release.
