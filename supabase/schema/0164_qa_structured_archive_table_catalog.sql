-- QA milestone 2: explicit FAIL-CLOSED coverage for every space-linked root
-- and all 35 presently discovered FK-linked child tables.
-- No content is copied or exposed, no archive/deletion is enabled.
create table if not exists private.qa_archive_table_policy (
  source_table text primary key,
  relation_kind text not null check(relation_kind in ('root','dependent')),
  disposition text not null default 'review_required'
    check(disposition in ('private_shared','owner_private','shared_only',
                          'media_excluded','system_excluded','review_required')),
  canonical_parent text,
  approved boolean not null default false,
  policy_note text not null default 'Needs explicit privacy and restore review',
  reviewed_at timestamptz,
  constraint child_parent_required check(
    relation_kind='root' or canonical_parent is not null)
);
alter table private.qa_archive_table_policy enable row level security;
revoke all on private.qa_archive_table_policy from public,anon,authenticated;

-- Discover every directly space-linked table; nothing is implicitly approved.
insert into private.qa_archive_table_policy
 (source_table,relation_kind,disposition,policy_note)
select distinct column_name_table,'root','review_required',
 'Space-linked table must be individually classified'
from (select c.table_name column_name_table
  from information_schema.columns c
  where c.table_schema='public' and c.column_name='space_id') root
on conflict(source_table) do nothing;
insert into private.qa_archive_table_policy
 (source_table,relation_kind,disposition,policy_note)
values('spaces','root','review_required','Relationship header/identity requires explicit archival policy')
on conflict(source_table) do nothing;

-- The 14 visibility-scoped personal/shared ROOT types already pass the
-- QA root-preview privacy tests; this does not approve nested restoration.
update private.qa_archive_table_policy
 set disposition='private_shared',approved=true,reviewed_at=now(),
     policy_note='Root scoped by created_by + visibility; child coverage still pending'
where relation_kind='root' and source_table=any(array[
 'activities','daily_checkins','goals','items_to_sort','memories','notes',
 'occasion_plans','places','reminders','saved_contacts','shared_trips',
 'space_counters','space_events','tasks']);

update private.qa_archive_table_policy
 set disposition='owner_private',approved=true,reviewed_at=now(),
     policy_note='Current personal-days-off owner is user_id, not a partner'
where source_table='personal_days_off';
update private.qa_archive_table_policy
 set disposition='system_excluded',approved=true,reviewed_at=now(),
     policy_note='Never export membership authorization records or active invitation secrets'
where source_table in ('space_members','space_invitations');

-- Every dependent row must be explicitly classified. The parent here is
-- the canonical *scope route*, not necessarily the only FK on the table.
with dependencies(source_table,canonical_parent) as (
  values
    ('activity_attention_snoozes','activities'),
    ('activity_comments','activities'),
    ('activity_component_reactions','activities'),
    ('activity_component_revisions','activities'),
    ('activity_components','activities'),
    ('activity_decisions','activities'),
    ('activity_revisions','activities'),
    ('couple_letter_reads','couple_letters'),
    ('memory_photo_revisions','memories'),
    ('memory_photos','memories'),
    ('note_images','notes'),
    ('note_references','notes'),
    ('occasion_budget_items','occasion_plans'),
    ('occasion_budget_log','occasion_plans'),
    ('occasion_plan_revisions','occasion_plans'),
    ('occasion_plan_steps','occasion_plans'),
    ('occasion_proposal_items','occasion_proposals'),
    ('occasion_proposals','occasion_plans'),
    ('partner_checkin_acknowledgements','partner_checkin_requests'),
    ('reminder_actions','reminders'),
    ('reminder_recipients','reminders'),
    ('saved_contact_revisions','saved_contacts'),
    ('scrapbook_invites','memories'),
    ('scrapbook_pages','memories'),
    ('shared_experience_comments','shared_experiences'),
    ('shared_experience_interests','shared_experiences'),
    ('shared_experience_reviews','shared_experiences'),
    ('shared_experience_revisions','shared_experiences'),
    ('task_checklist_checks','tasks'),
    ('task_checklist_items','tasks'),
    ('trip_attachments','shared_trips'),
    ('trip_flight_options','shared_trips'),
    ('trip_items','shared_trips'),
    ('trip_messages','shared_trips'),
    ('trip_revisions','shared_trips')
)
insert into private.qa_archive_table_policy
  (source_table,relation_kind,disposition,canonical_parent,policy_note)
select source_table,'dependent','review_required',canonical_parent,
 'Related data requires scope/owner and restore mapping validation'
from dependencies
on conflict(source_table) do nothing;

update private.qa_archive_table_policy
 set disposition='media_excluded',approved=true,reviewed_at=now(),
     policy_note='Media attachment or image table: never include bytes or Storage pointers'
where source_table in ('memory_photos','note_images','trip_attachments');

-- Read-only catalog audit never exposes record contents or a partner's
-- private-data totals to the client.
create or replace function private.qa_archive_catalog_coverage()
returns jsonb language plpgsql stable security definer set search_path='' as $fn$
declare
  me uuid:=auth.uid();
  sid uuid;
  n_unregistered_roots int;
  n_unregistered_dependents int;
  n_roots_pending int;
  n_children_pending int;
  n_approved int;
  n_excluded_media int;
  related jsonb;
begin
  if me is null then raise exception 'Sign in required'; end if;
  if (select count(*) from public.space_members where user_id=me)<>1 then
    return jsonb_build_object('has_space',false,
      'classification_complete',false,'safe_to_archive',false);
  end if;
  select space_id into sid from public.space_members where user_id=me;

  select count(*) into n_unregistered_roots
  from (select distinct c.table_name from information_schema.columns c
        where c.table_schema='public' and c.column_name='space_id'
        union select 'spaces') r
  where not exists(select 1 from private.qa_archive_table_policy p
    where p.source_table=r.table_name and p.relation_kind='root');

  related:=private.space_archive_dependency_inventory();
  select count(*) into n_unregistered_dependents
  from jsonb_array_elements(coalesce(related->'details','[]'::jsonb)) elem
  where not exists(select 1 from private.qa_archive_table_policy p
    where p.source_table=elem->>'table' and p.relation_kind='dependent');

  select count(*) into n_roots_pending from private.qa_archive_table_policy
    where relation_kind='root' and not approved;
  select count(*) into n_children_pending from private.qa_archive_table_policy
    where relation_kind='dependent' and not approved;
  select count(*) into n_approved from private.qa_archive_table_policy where approved;
  select count(*) into n_excluded_media from private.qa_archive_table_policy
    where disposition='media_excluded' and approved;

  return jsonb_build_object('has_space',true,
    'catalog_version',1,'total_tables',(select count(*) from private.qa_archive_table_policy),
    'approved_table_policies',n_approved,'root_types_pending',n_roots_pending,
    'dependent_types_pending',n_children_pending,
    'unregistered_root_types',n_unregistered_roots,
    'unregistered_dependent_types',n_unregistered_dependents,
    'media_types_excluded',n_excluded_media,
    'classification_complete',n_roots_pending=0 and n_children_pending=0
      and n_unregistered_roots=0 and n_unregistered_dependents=0,
    'safe_to_archive',false,'safe_to_separate',false,
    'reason','Every structured child, shared-only type, owner-specific type and restore mapping must be independently approved before full archive');
end $fn$;
revoke all on function private.qa_archive_catalog_coverage() from public,anon;
grant execute on function private.qa_archive_catalog_coverage() to authenticated;

create or replace function public.qa_archive_catalog_coverage()
returns jsonb language sql security invoker set search_path=''
as $fn$ select private.qa_archive_catalog_coverage() $fn$;
revoke all on function public.qa_archive_catalog_coverage() from public,anon;
grant execute on function public.qa_archive_catalog_coverage() to authenticated;
