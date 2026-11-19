# OneSpace QA — Lifecycle readiness and storage cleanup (19 November 2026)

**Environment:** Supabase QA project `ugwrpeduzyzrujkizqfo`, GitHub `BoyofKay/OneSpace`, draft PR #70. **Production unchanged.**

## Verified changes
- Authenticated, owner/partner-role-checked lifecycle preparation requests, status, cancellation and duplicate-job prevention.
- Privileged request implementation moved to private schema. Public authenticated RPC wrappers are `SECURITY INVOKER`.
- Added `space_lifecycle_readiness` read-only audit for 32 space-linked root tables, private/shared classification, unknown rows, verified archive metadata, direct attachment inventory, and reconciliation status.
- Existing `space_separation_preflight` delegates to the same audit.
- `safe_to_separate` **remains false** until dependent records, complete media-inclusive encrypted archives and the transition worker are verified; `root_archive_preconditions_met` reports partial readiness separately.
- The My Space Flutter draft page displays the actual safety blocker and never says a pending request is complete.
- Fixed data export wording: current JSON download excludes real attachments; it is **not** an encrypted separation archive.
- Account deletion stays disabled until the redesigned privacy-safe workflow is complete.

## Old QA Storage cleanup (completed)
- Source metadata initially showed 59 files in five legacy media buckets: 6 activity-media, 6 activity-voice, 41 memory photos, 2 note images, and 4 trip documents.
- None matched currently live direct attachment-reference rows. Preflight flagged them for reconciliation rather than treating absent database references as proof of an encrypted backup.
- Wrote QA-only service-role manifest that refused cleanup if current feature/attachment rows were present; preserved the newly registered push device and a live holiday preference.
- Deployed temporary secret-guarded QA-only worker. It deleted **59/59** through Supabase Storage API; worker reported 0 failures.
- Independently queried Storage and verified **0** legacy media objects remain. Confirmed 5 Auth users, 5 profiles, 3 spaces and 5 memberships remain intact.
- **Retired the one-time cleanup endpoint** (HTTP 410, JWT required) and dropped its privileged manifest RPC to eliminate reuse.

## QA regression observations
- Owner can stage/remove-partner or delete-space requests, but cannot leave.
- Invited partner can stage a leave request, but cannot remove someone or delete the space.
- Solo owner can request delete-space preparation, but cannot remove a nonexistent partner.
- Unsupported and duplicate requests rejected; a different user cannot cancel a job.
- Cancellation before export works; requested operations did not alter membership.
- Transaction-only notes classified correctly as private/shared. Note insert triggers automatically generated `record_action_history` rows; these are correctly flagged as unclassified **until a specific archival/audit-retention rule is implemented**.
- All synthetic test data and queued jobs were rolled back. No real test account was separated or deleted.
- The archive readiness endpoint is not accessible to `anon`.

## Unfinished, release-blocking work
1. Classification/ownership mapping and archive serialization for **35 dependent tables**, not just 32 root tables. Audit trail, tags, invitations, relationship-specific notifications, system metadata and embedded JSON media references require explicit policies.
2. Per-user, per-category **media-inclusive encrypted** private/shared archive creation, independent verification and tamper-proof integrity checks.
3. Secure key portability/recovery and authenticated external-save semantics; specifically P01 (what constitutes a verified successful download), per-user 30-day server TTL and confirmation policy.
4. Private installed-app archive downloads and safe private-only restoration, including dedupe and cross-partner data-isolation tests.
5. Idempotent, recoverable transition worker: owner-continuous clean space on removal/leave, invited partner unpaired, owner delete-space leaves both unpaired, storage cleanup after export.
6. Account-deletion orchestration and seven-day grace policy; account-level notifications and branded email.
7. Flutter analyzer/build, Android UI test on both phones, negative RLS tests, and production security review before release.

**Hard gate:** No real partner removal, space deletion or account purge should be enabled or described as completed until the encrypted archive and transition tests pass. The QA database preparation functions are live; Flutter changes are in draft PR #70, **not yet built or installed**.
