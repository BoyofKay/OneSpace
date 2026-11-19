# QA structured archive table catalog — 20 November 2026

## Contract
Archive and restore **structured private/shared content**. Exclude media bytes and uploaded files/documents, plus their Storage pointers. Never expose a person's private records to the other partner. Shared-history archives are reference-only when a new relationship begins.

## Deployed policy catalog
- SQL migration: 0164_qa_structured_archive_table_catalog.sql.
- **69 registered table types; 25 explicitly approved; 44 awaiting privacy/restore classification.**
- Root policies: 14 visibility-scoped private/shared content, 1 person-owned days off, 2 system-excluded account/invitation types, **12 pending**.
- Dependent policies: 3 approved media exclusions, **32 pending**.
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

## 12 root types still requiring explicit classification
calendar_partner_reminders, couple_letters, gesture_message_overrides,
gesture_schedules, gesture_templates, item_links, object_shares,
partner_checkin_requests, place_visits, record_action_history,
space_notifications, space_tags.

**Love Letters requires special handling:** author-private drafts and future
scheduled-open letters MUST NOT become visible to a partner through an archive
before their normal authorization rules allow it. Do not treat every row in a
shared space as shared content.

## 32 dependent types requiring explicit classification
activity_attention_snoozes, activity_comments, activity_component_reactions,
activity_component_revisions, activity_components, activity_decisions,
activity_revisions, couple_letter_reads, memory_photo_revisions,
note_references, occasion_budget_items, occasion_budget_log,
occasion_plan_revisions, occasion_plan_steps, occasion_proposal_items,
occasion_proposals, partner_checkin_acknowledgements, reminder_actions,
reminder_recipients, saved_contact_revisions, scrapbook_invites,
scrapbook_pages, shared_experience_comments, shared_experience_interests,
shared_experience_reviews, shared_experience_revisions, task_checklist_checks,
task_checklist_items, trip_flight_options, trip_items, trip_messages,
trip_revisions.

**Three excluded media-dependent types**: memory_photos, note_images,
trip_attachments. This exclusion does not yet prove there are no media URLs
embedded elsewhere; the structured sanitizer and coverage tests must remain.

## Next implementation sequence
1. Review actual columns, FK direction, ownership, RLS and visibility for every pending type. Explicitly model recipient-private actions and comments authored on shared content.
2. Resolve the five known multi-parent routes before serializing a child record; reject conflicting cross-space references.
3. Build the durable encrypted structured-data package including correct nested children and integrity manifest; download is its own external copy.
4. Restore private content into a fresh space with source-ID-to-new-ID remapping, idempotence and no old shared references; shared archive remains reference-only.
5. Prove full two-user lifecycle and finally enable leave/remove/delete behind the verified gate.

No real accounts, spaces, invitations, archives or media were deleted to create this catalog. Production was untouched. QA 468 is still the latest signed APK until a full integration milestone is ready for phone acceptance.
