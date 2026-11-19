-- QA-only review of shared root types against actual SELECT RLS policies.
-- These approvals mean "both current members may read this root type".
-- They DO NOT imply that descendants, encrypted packages or restoration work.
update private.qa_archive_table_policy
set disposition='shared_only',approved=true,reviewed_at=now(),
    policy_note='Existing RLS SELECT policy permits both active space members; structured serializer and restored shared-history reference remain pending'
where relation_kind='root' and disposition='review_required'
  and source_table in (
    'shared_experiences','partner_gestures','space_special_dates',
    'space_holiday_sources','spaces'
  );

-- Critical: do NOT approve couple_letters as plain shared content.
-- Drafts remain author-private and sent letters can be sealed until open_on.
update private.qa_archive_table_policy
set approved=false,disposition='review_required',
    policy_note='Must split author-private drafts and not-yet-open sealed letters from visible sent letters; status/open_on must not be bypassed by exporter'
where source_table='couple_letters';
