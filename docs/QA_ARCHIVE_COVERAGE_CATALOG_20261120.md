# QA structured archive table catalog — 20 November 2026

## Contract
Archive and restore **structured private/shared content**. Exclude media bytes and uploaded files/documents, plus their Storage pointers. Never expose a person's private records to the other partner. Shared-history archives are reference-only when a new relationship begins.

## Deployed policy catalog
- SQL migration: 0164_qa_structured_archive_table_catalog.sql.
- **69 registered table types; 69 explicitly classified; ZERO awaiting policy classification.**
- Root policies: 18 visibility-scoped private/shared content, 4 owner-private, 5 system-excluded and 7 member-shared types; **0 pending**.
- Dependent policies: 24 parent-scoped private/shared types, 5 member-shared types, 4 media exclusions and 2 operational exclusions; **0 pending**.
- Unregistered roots: 0; unregistered FK-linked dependent types: 0.
- Public QA status always says **safe_to_archive=false and safe_to_separate=false**, even if everything gets classified. The preview remains unverified and un-restorable.
- Synthetic future root + dependent tables were discovered as missing and blocked by the QA regression. Both synthetic tables were rolled back.
- Policy table resides in private schema with RLS enabled and no authenticated/anonymous direct table grants.

## Five additional root types reviewed and approved as member-shared scope
shared_experiences, partner_gestures, space_special_dates,
space_holiday_sources, spaces.

These classifications are grounded in existing RLS SELECT policies for both
active members. This approves **visibility scope**, not archive serialization,
encryption, restoration or destruction.

## Root classification completed
`item_links` and `record_action_history` are now approved after original-space endpoint/actor checks and exhaustive 15-kind event scope mapping.

**Love Letters protection implemented in QA 0184:** author-private drafts and future-open letters cannot be previewed by a partner before their normal open date. This has not yet been integrated into a complete archive.

## Dependent classification completed
`note_references`, `occasion_budget_items`, `occasion_budget_log`, `occasion_plan_revisions`, `occasion_proposal_items`, `reminder_actions` and `reminder_recipients` are all approved for their reviewed owner/space scopes.

**Four excluded media-dependent types**: memory_photos, note_images,
trip_attachments, memory_photo_revisions. This exclusion does not yet prove there are no media URLs
embedded elsewhere; the structured sanitizer and coverage tests must remain.

## Next implementation sequence
1. Review actual columns, FK direction, ownership, RLS and visibility for every pending type. Explicitly model recipient-private actions and comments authored on shared content.
2. Resolve the five known multi-parent routes before serializing a child record; reject conflicting cross-space references.
3. Build the durable encrypted structured-data package including correct nested children and integrity manifest; download is its own external copy.
4. Restore private content into a fresh space with source-ID-to-new-ID remapping, idempotence and no old shared references; shared archive remains reference-only.
5. Prove full two-user lifecycle and finally enable leave/remove/delete behind the verified gate.

No real accounts, spaces, invitations, archives or media were deleted to create this catalog. Production was untouched. QA 468 is still the latest signed APK until a full integration milestone is ready for phone acceptance.

## QA migration 0166 (deployed, regression passed)
- Additional owner-private roots: gesture_message_overrides, gesture_schedules, gesture_templates; authorship MUST be checked in the eventual serializer.
- Additional shared roots: partner_checkin_requests and space_tags; only the original pair may receive their old shared reference archive.
- Additional operational exclusions: calendar_partner_reminders, object_shares, space_notifications (not portable content or sharing permissions).
- Parent-scoped structured descendants: occasion_plan_steps, occasion_proposals, shared_experience_interests, shared_experience_reviews, trip_flight_options, trip_items, trip_messages.
- Photo revision records are media-excluded; narrative text in separately supported structured records remains in scope.
- **No portable archive, private restore or destructive action is authorized by the extra classifications.** 41 classified, 28 pending, four media classes excluded; fail-closed regression passes. Production unchanged.

## QA migrations 0167–0168: private trip child preservation (deployed, test passed)
- Adds owner-private vault mirroring for flight options, itinerary items, and trip messages on shared_trips with private visibility. Child authors must equal the private trip's owner; all source tables are explicitly whitelisted.
- Private→shared invalidates child snapshots. Shared→private resynchronizes eligible children; deletion tombstones deleted children. Existing private QA trips are backfilled after the vault type-constraint extension.
- Nested file/Storage pointers are sanitized while retaining written narrative. No physical media is backed up.
- Rollback-only QA regression passed for all transitions, owner mismatch rejection, sanitization and deletion tombstone. No real accounts, spaces or content removed.
- These snapshots are not encrypted downloadable archives; full nested serialization, restoration, relationship lifecycle and Production remain gated.

## QA migration 0170: indirect media/document pointers excluded (deployed, verified)
- The recursive structured sanitizer now removes scrapbook `photo_N_id` and `image_N_id` fields, upload/file metadata (`file_name`, `file_mime`, `file_size`, `voice_seconds`) and direct attachment/document/media ID keys.
- Captions, notes, original written text and normal non-storage hyperlinks remain intact.
- QA regressions for written text, nested private-trip package, owner-only root snapshots and the new indirect-ID test all pass.
- QA had zero restorable vault root/dependent rows at migration time; no existing snapshots needed re-sanitizing. Future migrations need a backfill check if data exists.
- No changes to archive availability, encryption, restoration or lifecycle safety gates. Production unchanged.

## QA migrations 0171–0174: private checklists preserved and previewed (deployed and tested)
- The `tasks` private root is already mirrored. Added owner-scoped dependent mirroring for `task_checklist_items` and `task_checklist_checks`, including edits, deletes, visibility transitions, and existing private data backfill.
- For private tasks, `created_by` for a checklist item and `user_id` for a completed check must equal task owner; check `task_id` must resolve through the same checklist item. Partner-authored historical rows cannot be silently transferred into a new private snapshot.
- Explicit catalog classification updated to **43 approved / 26 pending** (4 root types and 22 dependent types still pending).
- Read-only owner-scoped nested checklist preview contains root, items and checks with a SHA-256 payload checksum and rejects corrupt vault snapshots and partner-ownership contamination. Anonymous access blocked.
- Both rollback-only QA regressions passed. Synthetic rows were rolled back. This preview is **not an encrypted download, a verified archive, or a functioning restore**. Lifecycle safety gates remain false.

## QA 0175 — revoked operational states excluded
- `activity_attention_snoozes`: per-user attention delay is transient state; do not restore obsolete snoozes. The underlying activity remains eligible.
- `scrapbook_invites`: historical invitation/access permissions are not portable; never restore an old partner's collaboration grant. Original memory content remains separately classified.
- Both tables now `system_excluded`; after the QA regression, **45 approved of 69; 24 pending (4 roots, 20 dependents)**. This classification alone does not permit archive generation, deletion or restoration.

## QA 0181 — recipient-scoped shared-experience written history (deployed, tested)
- Classified `shared_experience_comments` and `shared_experience_revisions` as `shared_only`, following their existing member-shared parent `shared_experiences`. **47/69 approved; 22 pending (4 root, 18 dependent)**.
- A member may see all live shared comments, but a comment the other partner archived is excluded from that member's archive preview. The comment's author can still include their own archived text. Reply pointers to unavailable/hidden comments are removed to avoid exposing private comment identifiers.
- Historical before/after snapshots retain ordinary written descriptions but omit media paths and scrapbook photo IDs through the recursive sanitizer.
- Current-pair authorship, recipient-only scope, deterministic digest, outsider-denial, incomplete-lineage rejection and non-restorable shared-history flags were verified in a rollback-only two-account regression. **No completed encrypted shared archive or shared-history restoration is claimed.**

## QA 0182–0186 — written nested history reviewed and tested
- **13 new table types** classified with per-root and per-recipient privacy; **60/69 approved, 9 pending**.
- Private/shared parent invariants apply to scrapbook pages and editable revision history; no other partner's old contributions may silently be claimed as new private records.
- Activity components, comments, reactions, decisions and two audit streams are rendered into deterministic, capped structured previews; recursive media/file path redaction preserves textual captions.
- Love Letters drafts and future-open sent letters remain author-private; read receipts and hidden replies are restricted by real open status.
- Place visit captions remain while old memory/trip navigation IDs are inert and stripped, cross-space associations rejected.
- Check-in acknowledgements are accessible only to the original sender/recipient of a responded request, as reference-only history.
- Five synthetic two-account rollback-only QA regressions passed, including outsider requests, media leaks, digest integrity, and share→private collisions. **No portable full archive, trusted restore, or destructive lifecycle permission is implied.**

## QA 0187–0194 — 69/69 review complete, lifecycle still blocked
- Reminders: recipients/actions preserve user-written completion and follow-up history; transient scheduling, snooze and notification state excluded. Private recipient must be original owner; shared recipients/actors belong to pair.
- Occasion budget items, logs, revisions and proposal-item joins: both ends constrained to the same original plan and space. Keep written budget/audit details, recursively strip media references and avoid replaying orders or purchases.
- Note references/item links: both polymorphic endpoints must exist in same original space and be recipient-visible. A shared link never exposes a private target; private target creator must be original owner. Former-partner shared creators rejected.
- Action history: all 15 record kinds mapped, including archived comment author privacy and check-in request pair lineage. An absent or foreign-space source is rejected rather than silently dropped.
- **Classification complete does not imply archive/restoration complete.** QA public catalog now explicitly reports `encrypted_portable_archive_complete=false`, `trusted_private_restore_complete=false`, `source_of_truth_cutover_complete=false`, `safe_to_archive=false` and `safe_to_separate=false`. Tests for future unregistered tables preserve fail-closed behavior.
- The present preview interfaces are individually scoped and not a 69-type complete encrypted archive. Full manifest completeness, durable verified archive, independent private restore and two-device acceptance remain next P0 priorities.

## QA 0195–0198 — honest source completeness versus classification
- **69/69 types privacy-classified does not equal 69/69 actual records captured**. The implemented root mirror currently covers 14 specified private source types, and dependent mirroring covers nine specific families. `qa_private_archive_completeness_preflight()` now tests missing/stale/orphan source-vault equality for those supported types.
- **Four remaining private/shared roots outside current root mirroring:** `couple_letters`, `item_links`, `place_visits`, `record_action_history`.
- **Fifteen private/shared dependents outside current child mirroring:** `activity_comments`, `activity_component_reactions`, `activity_component_revisions`, `activity_components`, `activity_decisions`, `activity_revisions`, `couple_letter_reads`, `note_references`, `occasion_budget_log`, `occasion_plan_revisions`, `occasion_proposal_items`, `reminder_actions`, `saved_contact_revisions`, `scrapbook_pages`, `trip_revisions`.
- **Not part of 14+9 source-vault mirroring:** four owner-private root families, seven shared-only root families, five shared-only dependents and operational/media-excluded types. Actual archive policy must separately capture eligible written content and exclude operational/media data.
- New owner-only QA preflight reports per-family counts and missing/stale/orphan/foreign lineage faults, never raw partner-private snapshots. Its canonical subset SHA-256 binds the original owner, source-space and all audited private snapshot hashes. Fingerprint issuance fails if any supported snapshot mismatches, or a future schema type is unreviewed. This fingerprint is **not authenticated archive provenance**, not a real portable encrypted archive and does not authorize restore/leave/remove/delete.
- Four rollback-only SQL tests independently exercised owner/partner isolation, corrupted/missing roots, missing/altered children, old shared-vault tombstones, source-text hash changes and new table schema drift. All fixtures were rolled back.

## QA 0199–0206 — source enumeration extended; not yet full archive
- Existing owner-private vault subset: **14 roots + 9 descendants** verified against source-of-truth rows and fingerprinted.
- Previously unmirrored private/shared source rows: **4 root + 15 dependent families** now counted with owner-specific SHA-256 over recursively sanitized content. These new source-only censuses **do not persist archived copies** and are not evidence of complete backups.
- Four owner-only roots are enumerated using creator/sender/owner/user-specific attribution, independently of partner privacy: gesture drafts, schedules, overrides and personal days off.
- Twelve shared-only types (7 roots, 5 dependents) have original-pair-scoped source counts/hashes. In shared experiences, archived comments remain visible to the original author only; check-in acknowledgements cannot be included before response or by unauthorized participants.
- **Category accounting: 46 private-eligible + 12 shared-only + 11 media/operational-excluded = 69 privacy-classified families.** It does NOT imply all source rows are counted: **shared rows in mixed-private/shared tables** remain an explicit independent serialization gap; complete multi-family durable encrypted packaging and restoration still do not exist.
- Audit history safety: actions taken by A on B's old shared comment cannot become either user's new private restorable records when B later archives it; missing audit parents still fail closed.
- `public.qa_archive_source_coverage_report()` returns per-recipient hashes and counts only, with `mixed_visibility_shared_rows_censused=false`, `full_per_row_source_manifest_complete=false`, `independently_verified_encrypted_archive=false`, `can_restore=false`, `safe_to_archive=false` and `safe_to_separate=false`.
