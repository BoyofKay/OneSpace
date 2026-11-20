# OneSpace QA — invitation and canonical branding closure
Require-Firebase-Config: true

## One signed QA APK only
- Source includes merged PR #74 (invitation signup/signin), PR #75 (approved
  exact tagline `Two of Us. One Space`), and PR #76 (stable QA signing
  certificate and aligned source for email templates), and PR #77 (safe
  certificate-check pipeline; original signing fingerprint remains required).
- Android package: `onespace.qa`.
- Dart target: `ONESPACE_ENV=qa`; QA Supabase project
  `ugwrpeduzyzrujkizqfo`. Production Supabase untouched.
- Assert original QA signing SHA-256
  `90375bb8d7dbd6527cca17f626da149534eaffe10076c38a5c69ac86a3aac043`.
  Any mismatch must fail the build; never silently rotate QA keys.
- Flutter analysis + tests, Firebase QA package, APK package name and signed
  APK publication must all pass before considering this release available.

## Real device acceptance before closing
1. Install QA APK **over** existing QA app (do not uninstall and lose a
   saved incoming invitation).
2. New invited user: latest invitation, signup, dedicated confirm-email page,
   click confirmation email, sign in, automatically join existing space.
3. Existing invited user: latest invitation, sign in, automatically join.
4. Wrong account cannot redeem; current invitation must not be treated as a
   replaced/expired link.
5. QA Supabase hosted Confirm signup + Reset password templates still need
   matching HTML applied in dashboard; source-only commit does not update
   hosted Auth settings. Send real emails and verify logo + link.
6. No QA record deletion, space/account separation or Production database
   changes during this release.

## Future roadmap (NOT an excuse to block safe invitation testing)
- Founder expressly authorizes a QA-only historical record reset if needed
  for structural redesign of ownership tables.
- Structured private and shared content must remain eligible for archive and
  restore. Uploaded media, photos and documents are **excluded** with a
  clear user-facing disclosure. Do not remove all archive/restore features.
- Do not enable destructive lifecycle actions until ownership and structured
  restore are proven safe.

## Milestone 1 invitation and branded QA release verification (20 November 2026)
- Release source includes merged PR #102 (canonical **Two of Us. One Space** tagline in themes, strings and historical documentation; broader brand regression) and merged PR #103 (newest QA invitation source, original-space after-login handoff, already-joined idempotence and single contextual join card).
- Signed QA Android APK only: `onespace.qa`, `ONESPACE_ENV=qa`, QA Supabase `ugwrpeduzyzrujkizqfo`, original trusted preview signature; no Production writes. Existing workflow must test and sign before publishing one APK.
- Before calling Milestone 1 closed: install **over** previous QA on both devices, exercise invitation as a **new email-confirmed account** and as an **already-existing account**, correct/wrong email and reused/replaced/expired codes, standalone confirmation screen, and sender branding; confirm app opens one join panel then original existing space, no three setup cards.
- Real hosted Supabase signup/forgot-password templates and delivered emails still require external/manual verification. No space or account deletion, leave, partner removal, or automatic cleanup while full structured archive+restore milestone is incomplete. Media/documents excluded from structured archive by design.

## Final QA Milestone 1 handoff candidate — 0215
- This signed **QA-only** release supersedes the failed test-gated attempt 0.1.469 and contains merged PR #102 canonical tagline, PR #103 invitation state, PR #104 corrected confirmation-page scroll test and author-private future Love Letter metadata, PR #105 email-confirmed recipient invitation discovery fallback and secure pending-code persistence.
- Required: full Flutter analysis and tests PASS, QA Firebase registration, package `onespace.qa`, backend `ugwrpeduzyzrujkizqfo`, original test signing certificate SHA-256 `90375bb8d7dbd6527cca17f626da149534eaffe10076c38a5c69ac86a3aac043`.
- Device sign-off still requires both Android devices and real hosted QA confirmation emails. Structured encrypted archive+restore and destructive space/account lifecycle remain separate blocked milestones; uploaded media/documents explicitly excluded from future structured archives.

## Rebuild after verified invitation test timeout repair — 20 Nov 2026
- Exact source includes merged **PR #111**: `test/qa_invitation_handoff_contract_test.dart` explicitly mocks `FlutterSecureStorage` for the widget test. Focused [GitHub CI run #44646241623](https://github.com/BoyofKay/OneSpace/actions/runs/44646241623) passed, replacing failed 10-minute secure-store timeout from the prior QA release workflow #44644326927. No real-device secure storage implementation was changed.
- Includes #102 canonical tagline **Two of Us. One Space**, #103/#105 latest-recipient invitation recovery, single contextual join, confirmation/after-sign-in handling, #104 private future Love Letter metadata, and #110 read-only .osa private task/trip rehearsal.
- **Trigger one new signed QA APK** with full Flutter analysis/tests + QA Firebase config + Android package `onespace.qa`, QA Supabase URL `https://ugwrpeduzyzrujkizqfo.supabase.co` and original certificate `90375bb8d7dbd6527cca17f626da149534eaffe10076c38a5c69ac86a3aac043`. Fail closed on any mismatch.
- Do not mark Milestone 1 accepted until both physical Android phones prove latest invitation (new/existing accounts), hosted branded email confirmation/password recovery, actual join behavior and push notifications. No uninstall; preserve pending invitations. No Production content changes or relationship/account deletion.

## P0 black-screen recovery candidate — R468 regression
- **Reported impact:** installed QA app remains entirely black on launch beginning with R468, potentially affecting both R468 and subsequent releases. This is a **P0** blocker. Do not claim launch-ready from static Flutter tests.
- **Source:** merged PR #113, commit `4625aa84f435facd8f6bd828d40b6bec1dece8eb`; R464→R468 introduced a native `onespace/environment` package identity call before Supabase initialization without a timeout. Root cause on the affected phones remains unproven until device logs/runtime acceptance.
- **Mitigation:** Android app/package identity verification now times out safely after six seconds instead of hanging forever; verifies QA `onespace.qa` against QA backend only and fails closed. Supabase secure-session initialization is bounded with an explanatory error. The first Flutter frame has a reliable light theme and the sole approved tagline **Two of Us. One Space**, independent of theme/translation loading; Android native launch surface is not silently black in night mode.
- **Tests:** targeted startup/identity/widget regression and broad QA Flutter CI passed on PR #113. Installed QA APK emulators are separate additional checks; their running/unknown state must not be represented as successful evidence. Actual device behavior cannot be inferred from emulator/build success.
- **Release:** one signed QA APK for `onespace.qa` and QA Supabase only, original trusted QA certificate + Firebase package check mandatory. Do NOT clear app storage, uninstall an already installed QA app or delete any database content to fix startup. Install newer QA APK **over** existing one to preserve saved invitation, then verify first app frame, sign in, device unlock, invitation handoff and push on both Android devices.
- **Failing cases:** if still black, capture Android logcat around launch and whether a logo/startup error ever appears; only then consider graphics/engine-specific workarounds. Do not rotate signing keys, switch backends, relax RLS or enable destructive lifecycle actions.
