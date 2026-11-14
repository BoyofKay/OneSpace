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

## R18 — one source-only verification gate (no APK)

Validate the immersive theme changes, occasion shopping ledger UI, private source links, automatic personal themes and regression tests at commit 2e35c04d3815b5684091e6abdbbc0fa72093db1b. This gate must run only Flutter dependency verification, analyzer and tests; do not modify release/READY_TO_BUILD.md or build/publish an APK. Current R12–R17 release remains unchanged.

## R18 corrected analyzer recheck (no APK)

Source at bf1797724bfe2b9f108d590c32f2f465b8495ab8 fixes the R18 compact ternary opacity syntax reported by verify-only run 43459943995. Run one corrected source validation (lockfile, analyzer, tests). Do not run signing or APK publication.

## R18 corrected holiday expectation — final verify only

Run source-only analyzer and Flutter tests against 5ba059836cc7a84b8dc8d3193c0ef1664c6c57d8. The previous verify-only job passed analysis and 176/177 tests; the sole failure was an outdated Dec 25 Winter expectation replaced by dedicated Christmas theming. No APK/release marker changes.

## R19 acceptance-feedback source-only verification

Verify R19 at a6be135f3f89c4f620c9fb4258dfc18dc8771b0c with lockfile, Flutter analyze and all Flutter tests. Covers biometric/local lock, first-name, To-do nested cycle checklists, Notes photos, mentions, experiences and gesture UX. Do not build/sign/release APK or touch test accounts. Existing R12–R17 APK remains the baseline.

## R19 post-analyzer cleanup / verify only

R19 fix removes two unused imports flagged by run 43519852832, with no Dart compile errors. Re-run analyzer plus tests on 016ae9f6a7124450f19986b75f6c0bcf41508e8d. Do not build or release an APK, reset accounts or change the release marker.

## R19 final source-only verification after test corrections

Run verify-only against d5c9e6c01e8945d83417f1760e0e482160fb0705. Previous verify passed analyzer and failed exactly four tests due outdated lock thresholds and test-only unbound mention pickers. Those are now addressed. No APK, no release, no account reset.

## R20 release-candidate strengthening — source verification

Source to verify: 00c62cd6e3a1903acf9652a29217cf809fa76fae

The in-app 'Save a link or idea' option is removed while Android external Share -> OneSpace handling remains. Improvements: lazy checklist subscriptions, next-day cycle refreshing, enabling mention chooser when changed from private to shared, cached saved-login first name, contextual share intake heading, no dead external-platform buttons. Verify Flutter 3.50 deps/analyze/tests. DO NOT build an APK until verification passes and the separate release marker is updated.


## R21 pre-release verification (2026-11-14)
- Compile and test latest source after safe legacy task consolidation, independent partner checkmarks, narrower RLS policies, and camera-first searchable Memories.
- Do not publish an APK until the test suite passes and release gate is explicitly updated.


## R21 Contacts and legacy Lists gate
Run Flutter analyze + tests after Android native contact integration, vCard intake and retirement of empty legacy Lists backend.


## R22 First-class Reminders verification — 2026-11-14
- Includes new RLS reminders, independent recipient states/history, due cron notifications, Today/Remember reminders link and optional parent links.
- No push token or Firebase project is added yet. Compile/test with pinned Flutter dependencies; do not produce APK from source-only commits.


## R22 final source verification gate
- Unified sign-in with biometric/PIN unlock for an existing valid session.
- Reminder editor, per-recipient outcome/snooze, actionable notification deep links, global search.
- Run analyzer and all Flutter widget tests after latest source and schema 0080–0082; do not build APK here.


## R22 Analyzer repair pass
- Fixed unsupported OutlinedButton tooltip property and unified auth widget test getter.
- Recheck all Reminders and checklist navigation changes at this commit; fail closed before APK publishing.


## R23 feature integration gate — 2026-11-14
- Notes 2.0 Flutter Quill 11.6.0, lockfile pinned, rich Delta storage, existing privacy and optimistic version checks.
- Occasion shopping options, delivery warnings, preference ratings, order statuses and proposed combination save.
- Checklists selected weekdays, every N days/weeks, US federal holiday and personal day-off exceptions, optional IANA timezone.
- Run Flutter analyze and full test suite before Android release.


## R23 complete source compile gate
- Dependency lockfile for flutter_quill 11.6.0 committed.
- Check Note editor, Occasion combinations, recurrence schedule controls, timezone handling and tests; fail closed before APK.


## R23 source reconstruction acceptance
Recompiled both editors after removing malformed duplicate fragments; verify Quill 11.6.0, Occasion Planner, advanced checklist code, tests with pinned lockfile.
