# QA structured archive table catalog — 20 November 2026

## Contract
Archive and restore **structured private/shared content**. Exclude media bytes and uploaded files/documents, plus their Storage pointers. Never expose a person's private records to the other partner. Shared-history archives are reference-only when a new relationship begins.

## Deployed policy catalog
- SQL migration: 0164_qa_structured_archive_table_catalog.sql.
- **69 registered table types; 41 explicitly approved; 28 awaiting privacy/restore classification.**
- Root policies: 14 visibility-scoped private/shared content, 4 owner-private types, 5 system-excluded operational/account types, 7 member-shared types, **4 pending**.
- Dependent policies: 4 approved media exclusions, 7 parent-scoped content types, **24 pending**.
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

## 4 root types still requiring explicit classification
couple_letters, item_links, place_visits, record_action_history.

**Love Letters requires special handling:** author-private drafts and future
scheduled-open letters MUST NOT become visible to a partner through an archive
before their normal authorization rules allow it. Do not treat every row in a
shared space as shared content.

## 24 dependent types requiring explicit classification
activity_attention_snoozes, activity_comments, activity_component_reactions,
activity_component_revisions, activity_components, activity_decisions,
activity_revisions, couple_letter_reads,
note_references, occasion_budget_items, occasion_budget_log,
occasion_plan_revisions, occasion_proposal_items,
partner_checkin_acknowledgements, reminder_actions,
reminder_recipients, saved_contact_revisions, scrapbook_invites,
scrapbook_pages, shared_experience_comments, shared_experience_revisions, task_checklist_checks,
task_checklist_items, trip_revisions.

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
