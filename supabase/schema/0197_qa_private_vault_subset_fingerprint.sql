-- QA 0197: reproducible, owner-bound digest of ONLY the 23 currently
-- mirrored private root/dependent types. Never claim all 69 are archived.
-- No plaintext data, independent archive authenticity, or restoration API.
create or replace function private.qa_private_vault_subset_fingerprint()
returns jsonb language plpgsql stable security definer set search_path='' as $fn$
declare
 me uuid:=auth.uid();
 sid uuid;
 r jsonb;
 c jsonb;
 roots text[]:=array[
  'activities','daily_checkins','goals','items_to_sort','memories','notes',
  'occasion_plans','places','reminders','saved_contacts','shared_trips',
  'space_counters','space_events','tasks'];
 children text[]:=array[
  'occasion_budget_items','occasion_plan_steps','occasion_proposals',
  'reminder_recipients','task_checklist_items','task_checklist_checks',
  'trip_flight_options','trip_items','trip_messages'];
 n bigint;
 data_size bigint;
 text_hash text;
begin
 if me is null then raise exception 'Sign in required';end if;
 if (select count(*) from public.space_members m where m.user_id=me)<>1
 then raise exception 'Single relationship membership required';end if;
 select space_id into sid from public.space_members where user_id=me;
 r:=private.qa_private_archive_completeness_preflight();
 c:=private.qa_private_archive_child_mirror_preflight();
 if r->>'root_snapshot_mirror_consistent'<>'true'
    or c->>'supported_child_mirrors_consistent'<>'true'
 then raise exception 'Private vault subset is incomplete, stale or orphaned';end if;
 if (r->>'mirrored_root_types_checked')::int<>14
   or (c->>'mirrored_child_types_checked')::int<>9
   or jsonb_array_length(r->'private_shared_roots_not_in_current_mirror')<>4
   or jsonb_array_length(r->'private_shared_dependents_not_in_current_mirror')<>15
 then raise exception 'Archive schema scope changed; re-review required';end if;

 -- Hash snapshots first, then concatenate ONLY canonical source keys and
 -- fixed-size hashes in stable order. No uploaded photo, document or media
 -- file is included. Query snapshot is consistent within this statement.
 with snapshots as (
  select 'root'::text as kind, v.source_table, v.source_id,
    v.snapshot
  from public.personal_vault_records v
  where v.owner_id=me and v.source_space_id=sid
    and v.restorable and v.current_visibility='private'
    and v.source_table=any(roots)
  union all
  select 'child'::text, d.source_table,d.source_id,d.snapshot
  from public.personal_vault_dependents d
  join public.personal_vault_records parent
    on parent.owner_id=d.owner_id
     and parent.source_table=d.parent_table and parent.source_id=d.parent_id
     and parent.source_space_id=d.source_space_id
     and parent.current_visibility='private' and parent.restorable
  where d.owner_id=me and d.source_space_id=sid
    and d.restorable and d.source_table=any(children)
 ), rows as (
  select kind,source_table,source_id,
    octet_length(convert_to(snapshot::text,'UTF8')) as size,
    encode(extensions.digest(
       convert_to(snapshot::text,'UTF8'),'sha256'),'hex') as row_hash
  from snapshots
 )
 select count(*),coalesce(sum(size),0),
   encode(extensions.digest(convert_to(
     'onespace.qa.private.vault-subset.v1|'||me::text||'|'||sid::text||'|'||
     coalesce(string_agg(
        kind||'|'||source_table||'|'||source_id::text||'|'||row_hash,
        E'\n' order by kind,source_table,source_id::text),''),
     'UTF8'),'sha256'),'hex')
 into n,data_size,text_hash from rows;
 if n>5000 or data_size>8388608 then
   raise exception 'Private subset exceeds fingerprint safety limits';end if;
 if n<>coalesce((r->>'private_source_rows_checked')::bigint,0)
        +coalesce((c->>'child_source_rows_checked')::bigint,0)
 then raise exception 'Private source-vault record counts drifted';end if;

 return jsonb_build_object(
   'schema','onespace.qa.private-vault-subset-fingerprint.v1',
   'source_space_id',sid,'owner_id',me,
   'mirrored_root_types',14,'mirrored_child_types',9,
   'root_records',(r->>'private_source_rows_checked')::int,
   'child_records',(c->>'child_source_rows_checked')::int,
   'snapshot_record_count',n,
   'snapshot_plaintext_bytes',data_size,
   'subset_sha256',text_hash,
   'root_mirror_verified',true,'supported_child_mirrors_verified',true,
   'all_69_types_packaged',false,
   'server_signed',false,'is_verified_archive',false,
   'can_restore',false,'safe_to_archive',false,'safe_to_separate',false,
   'warning','This SHA-256 fingerprints a checked owner-private vault subset only. It is not a trusted server-signed 69-type encrypted archive.'
 );
end $fn$;
revoke all on function private.qa_private_vault_subset_fingerprint()
 from public,anon,authenticated;
grant execute on function private.qa_private_vault_subset_fingerprint()
 to authenticated;

create or replace function public.qa_private_vault_subset_fingerprint()
returns jsonb language sql stable security invoker set search_path='' as $fn$
 select private.qa_private_vault_subset_fingerprint()
$fn$;
revoke all on function public.qa_private_vault_subset_fingerprint()
 from public,anon;
grant execute on function public.qa_private_vault_subset_fingerprint()
 to authenticated;
