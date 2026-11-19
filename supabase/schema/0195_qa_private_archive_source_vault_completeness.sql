-- QA 0195: independently compare owner-private source rows with
-- owner-only Personal Vault snapshots before ANY archive issuance.
-- Reporting only. This function can never mark a lifecycle archive ready.
create or replace function private.qa_private_archive_completeness_preflight()
returns jsonb language plpgsql stable security definer set search_path='' as $fn$
declare
  me uuid:=auth.uid();
  sid uuid;
  root_table text;
  roots text[]:=array[
    'activities','daily_checkins','goals','items_to_sort','memories',
    'notes','occasion_plans','places','reminders','saved_contacts',
    'shared_trips','space_counters','space_events','tasks'];
  supported_children text[]:=array[
    'occasion_budget_items','occasion_plan_steps','occasion_proposals',
    'reminder_recipients','task_checklist_items','task_checklist_checks',
    'trip_flight_options','trip_items','trip_messages'];
  current_count bigint;
  missing_count bigint;
  stale_count bigint;
  orphan_count bigint;
  total_source bigint:=0;
  total_missing bigint:=0;
  total_stale bigint:=0;
  total_orphan bigint:=0;
  current_rows jsonb:='[]'::jsonb;
  unsupported_roots jsonb;
  unsupported_children jsonb;
  coverage jsonb;
  n_supported bigint;
begin
  if me is null then raise exception 'Sign in required';end if;
  if (select count(*) from public.space_members m where m.user_id=me)<>1 then
    raise exception 'Single current relationship membership required';
  end if;
  select m.space_id into sid from public.space_members m where m.user_id=me;
  coverage:=private.qa_archive_catalog_coverage();

  -- The explicit source families are a reviewed subset of the 69-table
  -- catalog. Future schema drift or changed classification fails closed.
  if (select count(*) from private.qa_archive_table_policy p
      where p.source_table=any(roots) and p.relation_kind='root'
        and p.disposition='private_shared' and p.approved)
       <>coalesce(array_length(roots,1),0) then
    raise exception 'Private root mirror schema changed: re-review required';
  end if;
  if (select count(*) from private.qa_archive_table_policy p
      where p.source_table=any(supported_children)
        and p.relation_kind='dependent'
        and p.disposition='private_shared' and p.approved)
       <>coalesce(array_length(supported_children,1),0) then
    raise exception 'Private child mirror schema changed: re-review required';
  end if;
  foreach root_table in array roots loop
    -- Validate *every* live owner-private record, not just records already
    -- present in the vault (which could silently omit whole data types).
    execute format(
      'select count(*),
        count(*) filter(where v.source_id is null),
        count(*) filter(where v.source_id is not null and
           v.snapshot is distinct from private.qa_structured_value(to_jsonb(t)))
       from public.%I t
       left join public.personal_vault_records v
         on v.owner_id=$1 and v.source_table=%L
           and v.source_id=t.id and v.source_space_id=$2
           and v.restorable and v.current_visibility=''private''
       where t.space_id=$2 and t.created_by=$1 and t.visibility=''private''',
      root_table,root_table)
    into current_count,missing_count,stale_count using me,sid;

    -- Mirrored-but-deleted, reassigned or now shared source records must
    -- not remain eligible through the previous owner's vault.
    execute format(
      'select count(*) from public.personal_vault_records v
       left join public.%I t on t.id=v.source_id
       where v.owner_id=$1 and v.source_table=%L
         and v.source_space_id=$2 and v.restorable
         and v.current_visibility=''private''
         and (t.id is null or t.space_id is distinct from $2
           or t.created_by is distinct from $1
           or t.visibility is distinct from ''private'')',
      root_table,root_table)
    into orphan_count using me,sid;
    total_source:=total_source+current_count;
    total_missing:=total_missing+missing_count;
    total_stale:=total_stale+stale_count;
    total_orphan:=total_orphan+orphan_count;
    current_rows:=current_rows||jsonb_build_array(jsonb_build_object(
       'source_table',root_table,'private_source_count',current_count,
       'missing_vault_count',missing_count,
       'stale_vault_snapshot_count',stale_count,
       'orphan_vault_count',orphan_count,
       'mirrored_sources_complete',
           missing_count=0 and stale_count=0 and orphan_count=0));
  end loop;

  select coalesce(jsonb_agg(p.source_table order by p.source_table),'[]'::jsonb)
    into unsupported_roots from private.qa_archive_table_policy p
    where p.relation_kind='root' and p.approved
      and p.disposition='private_shared'
      and p.source_table<>all(roots);

  select coalesce(jsonb_agg(p.source_table order by p.source_table),'[]'::jsonb)
    into unsupported_children from private.qa_archive_table_policy p
    where p.relation_kind='dependent' and p.approved
      and p.disposition='private_shared'
      and p.source_table<>all(supported_children);

  return jsonb_build_object(
   'schema','onespace.qa.private-archive-completeness-preflight.v1',
   'source_space_id',sid,'owner_id',me,
   'classified_source_types',coverage->'approved_table_policies',
   'classification_complete',coverage->'classification_complete',
   'mirrored_root_types_checked',array_length(roots,1),
   'private_source_rows_checked',total_source,
   'missing_private_root_snapshots',total_missing,
   'stale_private_root_snapshots',total_stale,
   'orphan_private_vault_snapshots',total_orphan,
   'per_root_family',current_rows,
   'private_shared_roots_not_in_current_mirror',unsupported_roots,
   'private_shared_dependents_not_in_current_mirror',unsupported_children,
   'root_snapshot_mirror_consistent',
     total_missing=0 and total_stale=0 and total_orphan=0,
   'dependent_mirror_completeness_verified',false,
   'owner_private_types_verified',false,
   'shared_only_types_verified',false,
   'per_table_source_manifest_complete',false,
   'trusted_encrypted_archive_complete',false,
   'ready_to_restore',false,
   'safe_to_archive',false,'safe_to_separate',false,
   'warning','Snapshot matching checks only the 14 existing owner-private root mirrors. Missing private/shared families, nested/owner/shared records, authenticity and restoration still block archival.'
  );
end $fn$;
revoke all on function private.qa_private_archive_completeness_preflight()
 from public,anon,authenticated;
grant execute on function private.qa_private_archive_completeness_preflight()
 to authenticated;

create or replace function public.qa_private_archive_completeness_preflight()
returns jsonb language sql stable security invoker set search_path='' as $fn$
 select private.qa_private_archive_completeness_preflight()
$fn$;
revoke all on function public.qa_private_archive_completeness_preflight()
 from public,anon;
grant execute on function public.qa_private_archive_completeness_preflight()
 to authenticated;
