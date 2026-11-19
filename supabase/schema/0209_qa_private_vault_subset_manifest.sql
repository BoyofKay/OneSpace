-- QA 0209: real, bounded per-record SNAPSHOT manifest for the 14-root
-- + 9-dependent private owner-vault families, with exact PostgreSQL JSONB
-- byte hashes. Not a 69-family archive or a restorable package.
create or replace function private.qa_private_vault_subset_manifest()
returns jsonb language plpgsql stable security definer set search_path='' as $fn$
declare
  me uuid:=auth.uid();
  sid uuid;
  expected jsonb;
  items jsonb;
  manifest_hash text;
  record_count bigint;
  byte_count bigint;
  root_count bigint;
  child_count bigint;
  max_item_bytes bigint;
  roots text[]:=array[
   'activities','daily_checkins','goals','items_to_sort','memories',
   'notes','occasion_plans','places','reminders','saved_contacts',
   'shared_trips','space_counters','space_events','tasks'];
  children text[]:=array[
   'occasion_budget_items','occasion_plan_steps','occasion_proposals',
   'reminder_recipients','task_checklist_items','task_checklist_checks',
   'trip_flight_options','trip_items','trip_messages'];
begin
 if me is null then raise exception 'Sign in required';end if;
 if (select count(*) from public.space_members sm where sm.user_id=me)<>1
 then raise exception 'Single original relationship required';end if;
 select space_id into sid from public.space_members where user_id=me;
 expected:=private.qa_private_vault_subset_fingerprint();
 if expected->>'owner_id'<>me::text
 or expected->>'source_space_id'<>sid::text
 or expected->>'root_mirror_verified'<>'true'
 or expected->>'supported_child_mirrors_verified'<>'true'
 or (expected->>'mirrored_root_types')::int<>14
 or (expected->>'mirrored_child_types')::int<>9 then
 raise exception 'Private source manifest lineage or coverage mismatch';end if;

 with selected as (
  select 'root'::text kind,v.source_table,v.source_id,
   null::text parent_table,null::uuid parent_id,v.snapshot
  from public.personal_vault_records v
  where v.owner_id=me and v.source_space_id=sid
    and v.restorable and v.current_visibility='private'
    and v.source_table=any(roots)
  union all
  select 'child'::text,d.source_table,d.source_id,
     d.parent_table,d.parent_id,d.snapshot
  from public.personal_vault_dependents d
  join public.personal_vault_records v on v.owner_id=d.owner_id
    and v.source_table=d.parent_table and v.source_id=d.parent_id
    and v.source_space_id=d.source_space_id and v.restorable
    and v.current_visibility='private'
  where d.owner_id=me and d.source_space_id=sid
    and d.restorable and d.source_table=any(children)
 ), digested as (
  select kind,source_table,source_id,parent_table,parent_id,
   snapshot::text as snapshot_json,
   octet_length(convert_to(snapshot::text,'UTF8')) bytes,
   encode(extensions.digest(convert_to(snapshot::text,'UTF8'),'sha256'),'hex') as sha
  from selected
 )
 select count(*),coalesce(sum(bytes),0),
   count(*) filter(where kind='root'),
   count(*) filter(where kind='child'),
   coalesce(max(bytes),0),
   coalesce(jsonb_agg(jsonb_build_object(
      'kind',kind,'source_table',source_table,'source_id',source_id,
      'parent_table',parent_table,'parent_id',parent_id,
      'snapshot_json',snapshot_json,
      'snapshot_sha256',sha,'snapshot_bytes',bytes)
     order by kind,source_table,source_id::text),'[]'::jsonb),
   encode(extensions.digest(convert_to(
     'onespace.qa.private.vault-subset.v1|'||me::text||'|'||sid::text||'|'||
     coalesce(string_agg(
       kind||'|'||source_table||'|'||source_id::text||'|'||sha,
       E'\n' order by kind,source_table,source_id::text),''),
      'UTF8'),'sha256'),'hex')
 into record_count,byte_count,root_count,child_count,max_item_bytes,
      items,manifest_hash
 from digested;
 if record_count>5000 or byte_count>8388608 or max_item_bytes>524288
 then raise exception 'Source snapshot manifest exceeds bounded read limits';end if;
 if root_count<>(expected->>'root_records')::int
   or child_count<>(expected->>'child_records')::int
   or record_count<>(expected->>'snapshot_record_count')::int
   or byte_count<>(expected->>'snapshot_plaintext_bytes')::int
   or manifest_hash<>expected->>'subset_sha256'
 then raise exception 'Source snapshots changed during manifest construction';end if;

 return jsonb_build_object(
  'schema','onespace.qa.private-vault-subset-manifest.v1',
  'owner_id',me,'source_space_id',sid,
  'root_types_in_scope',14,'dependent_types_in_scope',9,
  'record_count',record_count,'root_record_count',root_count,
  'child_record_count',child_count,
  'snapshot_plaintext_bytes',byte_count,
  'subset_sha256',manifest_hash,
  'records',items,
  'media_included',false,'documents_included',false,
  'all_69_types_packaged',false,'source_manifest_scope_complete',true,
  'archive_issued',false,'server_signed',false,'is_verified_archive',false,
  'can_restore',false,'safe_to_archive',false,'safe_to_separate',false,
  'warning','These are owner-only plaintext snapshots of 23 already-mirrored families. Encrypt locally before storing/exporting; NOT a complete relationship archive or permission for deletion.'
 );
end $fn$;
revoke all on function private.qa_private_vault_subset_manifest()
 from public,anon,authenticated;
grant execute on function private.qa_private_vault_subset_manifest()
 to authenticated;

create or replace function public.qa_private_vault_subset_manifest()
returns jsonb language sql stable security invoker set search_path='' as $fn$
 select private.qa_private_vault_subset_manifest()
$fn$;
revoke all on function public.qa_private_vault_subset_manifest()
 from public,anon;
grant execute on function public.qa_private_vault_subset_manifest()
 to authenticated;
