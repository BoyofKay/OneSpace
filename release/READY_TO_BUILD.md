# OneSpace Android QA — private data migration and archive readiness (2026-11-19)

Require-Firebase-Config: true
Branch: qa/lifecycle-first-slice-20261119
Deliverable: signed OneSpace **QA** Android APK only, not Production AAB or Production backend.

This incorporates the preceding screenshot fixes:
- Change Password Update disabled until valid; Cancel aligned beside it.
- Invite sharing buttons aligned, resend confirmation; Today duplicate actions removed.
- QA HTTPS /qa-invite/ link and associated QA-only Android App Link. Production remains /app-invite/.
- Branded reset template prepared; QA Supabase Auth SMTP must still be configured by account owner for sender support@onespace.live.

QA data migration (migrations applied to QA only):
- 11 account-owned private source records (including personal days off), with 18 owner-authored dependent records protected in new Personal Vault tables, including original visibility and ownership.
- 14 typed private-source mirrors; private->shared visibility changes no longer eligible for private restore.
- On intentional deletion, private Vault items are tombstoned to prevent old deleted content reappearing; relationship retirement must use guarded context.
- Exactly 59 media objects matched to 59 source database records and accurately classified as shared; zero missing or unclassified paths.
- My Space readiness page displays authenticated user's own protected private record and dependent record counts.
- Lifecycle policy and unit tests for owner continuity vs partner leave, owner remove/delete space, cascading account deletion.

Security gate:
- Personal Vault records and inventories have RLS enabled and NO client grants; only safe count summary is exposed.
- Actual encrypted media-inclusive archive generator, verified per-user delivery, owner-continuity backend cutover, leave/remove/delete, and private-only restore are NOT yet enabled. The legacy QA account delete flow remains disabled. No user data or media has been deleted.
- The temporary archive early-deletion condition remains explicit verified user download, never automatic app-private copy, or 30 days.
- Do not claim complete separation functionality in release notes.

CI: resolve locked dependencies, flutter analyze, flutter test, sign APK, verify QA application ID and test certificate. Only publish verified QA artifact.
