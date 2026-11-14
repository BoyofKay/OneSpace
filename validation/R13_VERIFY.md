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


## R23 single analyzer defect fixed
Restored missing Occasion estimated-arrival picker; previous analyzer found only this remaining compile error. Run complete tests.


## R24 Firebase Messaging transport compile gate
- Firebase Core 5.1.0, Messaging 17.0.1 pinned with optional Android Google services build configuration.
- Auth-unlocked token registration, OS notification permission, navigation to in-app feed, explicit sign-out unregister.
- Supabase 0087 device ownership RLS, private per-device outbox, service-role protected claim/ack.
- Deployed Edge worker uses OAuth2 FCM HTTP v1 only after secure service credentials configured.
- Rollback SQL 0012 PASSED. Validate all Dart tests and Flutter static analysis.


## R26 Scrapbook Studio source verification
- Four designed scrapbook templates, multi-page editor, partner invite/accept RLS, photo slot validation, camera/gallery, image tags manager, PNG Android MediaStore export.
- Two new migrations (0091/0092) applied; rollback-only regression SQL 0014 passed private visibility, uninvited rejection, accepted contribution and foreign-photo blocking.
- Run analyzer, full Flutter tests and Android test suite; do not publish signed preview before green.


## R26 final analyzer retest
Removed one unused photo-local warning and upgraded template gallery to actual responsive page previews. Verify source at this commit after all edits.


## R27 Trips research source gate (not a published APK)
- Added RLS trip_flight_options schema 0093 (candidate airfare, provider links, flexibility, stops, baggage, scores, booking state).
- Rollback SQL privacy regression 0015 PASS.
- TripDetail links a manual comparison board to existing itinerary; booking conversion requires explicit user confirmation and does not purchase flight.
- Verify complete Flutter analyzer and tests. This is source-only until the separate R27 release marker.


## R28 — Shared experiences build safety gate

Run Flutter analyze and tests for date persistence and deterministic day-based suggestions (no external recommender, no live API). This is source-only validation: do not trigger APK build or change accounts, memberships or stored content.


## R27 Trips and linked checklists verification
- 0094 generates idempotent travel-ready checklists inside existing Remember To-do and Checklists; no duplicate task module.
- Four templates include travel essentials, leaving home, baby, pets, with independently tickable items.
- TripPreparationSection and PlansScreen focusTaskId deep link integrated.
- RLS regression 0016 passed private trip denial, shared partner visibility and idempotence.
- Re-verify full Flutter analysis and tests at this exact commit before R27 Android release.


## R27 full source final gate
Trip airfare choices are competing alternatives, so their prices are compared per currency rather than incorrectly summed. Verify final source before separate R27 signed preview.


## R29 — Live Experiences realtime + conflict and media-category regression

Source-only verification on current main. Flutter lockfile, full analyzer and tests for live experience UI; non-destructive shared planning status/date, stale-edit detection, document `docs/R29_SHARED_EXPERIENCES_REALTIME_QA.md`, no APK or production deployment during this gate. R25 device push remains untouched. Do not cancel previous successful verifications or reset the existing pair.


## R30 — partner interest votes and mutual picks (source-only verification)

Validate latest main source with committed Flutter lockfile, full `flutter analyze --no-fatal-infos` and `flutter test`. Scope includes the R30 live match filter/labels, partner preference view and update, deterministic suggestion priority and new unit tests. Supabase schema 0095 and rollback test 0016 already passed. No APK or release is authorized by this validation gate. Preserve both accounts, data, preview signature and Firebase delivery.


## R31 — Daily Connection request lifecycle (verify only)

Verify additive migration 0096 and rollback regression 0017 (server-side test already passed), plus Flutter dependency lock, full analyzer and all unit tests for the new pending/answered/expired filters, legacy records and expiry-safe reply UI. No APK in this verification-only gate. Keep both paired accounts, Firebase push and preexisting history unchanged.


## R31 final verification — expiry rounding and rollback regression refinements

Run full Flutter dependency resolution, analyzer and tests on this latest source after correcting the remaining-day rounding calculation. R31 backend rollback test 0017 rerun and PASS with the second-reply zero-affected RLS check. Do not build an APK or change preview signing, Firebase secrets or user data during this verification step.


## R32 — Optional Check-in Acknowledgments (source only)

Run exact committed Flutter dependency lock verification, analyzer and all automated tests on R32 source including `checkin_acknowledgement_rules_test.dart`. Supabase schema 0098 and rollback-only RLS regression 0018 already passed. No APK, no Firebase changes and no release marker update as part of this validation; R31 APK 408 was independently triggered from its earlier immutable commit.


## R32 analyzer correction — source-only verification

R32 analyzer found one test-only nullable-map inference in `checkin_acknowledgement_rules_test.dart`. The test fixture now explicitly accepts dynamic nullable response fields. Re-run analyzer, committed dependency checks and full Flutter tests without touching release marker or building an APK.


## R33 — Android To-do and Checklists crash blocker, source verification

Full Flutter committed dependency lock check, `flutter analyze` and all `flutter test` including `checklist_list_loader_test.dart` after non-destructive task parsing hardening. Live backend task statistics checked and no old/new checklist rows deleted. Gate source changes only; do not release until green. Documentation `docs/R33_CHECKLIST_CRASH_BLOCKER_QA.md`. Existing push configuration, two users, signing certificate and shared/private data stay intact.


## R33 corrected legacy visibility fallback — final source gate

The initial full-suite CI found one compatibility failure in existing `widget_test.dart` (missing visibility expected shared). Restored original shared fallback while retaining null/malformed row crash isolation. Re-run all Flutter tests, analyzer and locked dependencies. Dual-account RLS read regression 0019 PASS. No database cleanup or APK until green.


## R34 — Checklist expansion runtime isolation (source only)

User confirms Release 409 crashes when expanding *any* checklist. New and old checklists share TaskChecklistPanel. Legacy target date not used by expansion; no DB deletion. R34 removes second realtime filter during expansion, applies exact cycle locally, wraps stream initialization and adds injected-stream widget tests that expand both new and legacy rows with target dates. Verify lockfile, full analyzer and all tests; never mark phone-tested until user confirms. No signed APK unless green.


## R34 exact tap-to-expand regression

After initial source gate, add widget tests that start with collapsed ExpansionTile, tap to expand actual TaskChecklistPanel, and assert no Flutter runtime exception with legacy target dates, new lists, per-user cycle checks and transport failures. Run full analyzer + all Flutter tests on final source commit. No data destruction, no APK before green.


## R34 final — in-app copyable stack diagnostics

R34 verifies exact interactive expand/collapse tests of old/new list contents and new `OneSpaceErrorFallback` stack trace text, with full flutter analyze/tests on final source. R34 first validation (run 40) passed. No deletion of legacy target dates or checklist data. Once final verification passes, run one signed Android preview build.


## R34 reproduced actual checklist crash: PageStorage bool restored as scroll double

Real tap-to-expand Flutter widget tests caught `_TypeError: type 'bool' is not a subtype of type 'double?'` in `ScrollPosition.restoreScrollOffset` within `EditableText` of the nested subtask TextField. Fix removes the ExpansionTile PageStorageKey and passes a ScrollController(keepScrollOffset:false) to the nested TextField. The regression test intentionally retains a PageStorageKey ancestor to prevent recurrence. Re-run full Flutter dependencies, analyzer and all tests before shipping. No database cleanup needed and no data changed.


## R35 — Occasion preparation milestones connected to Reminders (source-only verification)

Run full committed Flutter dependencies, analyzer and entire test suite (including `occasion_preparation_rules_test.dart`) against R35, and confirm cross-module deep links from reminder to the exact source object. Additive Supabase 0099 deployed; rollback-only two-account SQL 0020 PASS. Do not create automatic reminders, modify existing data, change Firebase config, or release an APK until source gate succeeds.


## R36 — Thoughtful private love self-reminders (source-only verification)

R36 adds a manual personal-only schedule choice in A Little Love and a reminder deep link back to the gestures tab. Migration 0100 deployed, rollback-only RLS test 0021 passed. Run locked dependencies, full analyzer and Flutter tests including `love_prompt_rules_test.dart`. No change to automated gestures config, FCM, privacy, pairing, or published Release 411 (already pinned). Do not build R36 APK unless green.


## R36 final UX verification — explicit local hour labels

Updated gesture self-reminder time suggestion chips to label 9 AM, 6 PM and 9 PM explicitly rather than imply actual work schedule. Run the entire Flutter analyzer/test suite on final current source and preserve source-only gate; signed R35 Release 411 remains pinned to prior version.


## R37 — Hands-free checklist readout (source-only verification)

New Android TextToSpeech and iOS AVSpeechSynthesizer MethodChannel plus a read-only Flutter checklist voice sheet. Test native bridge invocation through mock channel, active/unchecked item script privacy, lifecycle stop, and previous R34 checklist expansion tests. Run exact Flutter dependencies, analyzer and entire test suite before any APK. No Supabase schema changes or Firebase changes; voice never updates checkmarks. Real Android TTS and native Kotlin compilation must pass a separate signed preview build; iOS requires separate macOS compiler verification.
