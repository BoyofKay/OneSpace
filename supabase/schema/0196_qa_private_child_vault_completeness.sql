-- QA 0196: inspect the nine CURRENTLY mirrored dependent families.
-- This is a completeness audit only and cannot issue/restore an archive.
create or replace function private.qa_private_archive_child_mirror_preflight()
returns jsonb language plpgsql stable security definer set search_path='' as $fn$
declare
 me uuid:=auth.uid();
 sid uuid;
 child_table text;
 parent_table text;
 parent_fk text;
 actor_field text;
 tables text[]:=array[
    'occasion_budget_items','occasion_plan_steps','occasion_proposals',
    'reminder_recipients','task_checklist_items','task_checklist_checks',
    'trip_flight_options','trip_items','trip_messages'];
 n bigint;
 missing_count bigint;
 stale_count bigint;
 foreign_count bigint;
 unrelated_count bigint;
 orphan_count bigint;
 total bigint:=0;
 missing_total bigint:=0;
 stale_total bigint:=0;
 foreign_total bigint:=0;
 unrelated_total bigint:=0;
 orphan_total bigint:=0;
 per_family jsonb:='[]'::jsonb;
begin
 if me is null then raise exception 'Sign in required';end if;
 if (select count(*) from public.space_members m where m.user_id=me)<>1
 then raise exception 'Single current relationship membership required';end if;
 select m.space_id into sid from public.space_members m where m.user_id=me;

 if (select count(*) from private.qa_archive_table_policy p
 where p.source_table=any(tables) and p.relation_kind='dependent'
    and p.disposition='private_shared' and p.approved)<>9
 then raise exception 'Child mirror catalog has changed';end if;
 foreach child_table in array tables loop
   if child_table like 'occasion_%' then
      parent_table:='occasion_plans';parent_fk:='plan_id';
   elsif child_table='reminder_recipients' then
      parent_table:='reminders';parent_fk:='reminder_id';
   elsif child_table like 'task_checklist_%' then
      parent_table:='tasks';parent_fk:='task_id';
   elsif child_table like 'trip_%' then
      parent_table:='shared_trips';parent_fk:='trip_id';
   else raise exception 'Unreviewed QA child mirror type';end if;
   actor_field:=case child_table
      when 'reminder_recipients' then 'recipient_id'
      when 'task_checklist_checks' then 'user_id'
      else 'created_by' end;

   execute format(
    'select count(*),
      count(*) filter(where v.source_id is null),
      count(*) filter(where v.source_id is not null
        and v.snapshot is distinct from private.qa_structured_value(to_jsonb(c))),
      count(*) filter(where c.%I is distinct from $1)
     from public.%I c join public.%I p on p.id=c.%I
     left join public.personal_vault_dependents v
       on v.owner_id=$1 and v.source_table=%L and v.source_id=c.id
         and v.parent_table=%L and v.parent_id=p.id
         and v.source_space_id=$2 and v.restorable
     where p.space_id=$2 and p.created_by=$1 and p.visibility=''private''',
     actor_field,child_table,parent_table,parent_fk,child_table,parent_table)
   into n,missing_count,stale_count,foreign_count using me,sid;

   unrelated_count:=0;
   if child_table='task_checklist_checks' then
     select count(*) into unrelated_count
       from public.task_checklist_checks checks
       join public.tasks t on t.id=checks.task_id
       where t.space_id=sid and t.created_by=me and t.visibility='private'
         and not exists(select 1 from public.task_checklist_items i
           where i.id=checks.item_id and i.task_id=t.id);
   end if;

   -- A previously mirrored child must no longer be active if deleted,
   -- reparented, promoted to shared or authored by a different partner.
   execute format(
     'select count(*) from public.personal_vault_dependents v
       left join public.%I c on c.id=v.source_id
       left join public.%I p on p.id=c.%I
      where v.owner_id=$1 and v.source_table=%L
        and v.source_space_id=$2 and v.restorable
        and (c.id is null or p.id is null
          or p.space_id is distinct from $2
          or p.created_by is distinct from $1
          or p.visibility is distinct from ''private''
          or c.%I is distinct from $1
          or v.parent_table is distinct from %L
          or v.parent_id is distinct from p.id)',
     child_table,parent_table,parent_fk,child_table,actor_field,parent_table)
   into orphan_count using me,sid;

   total:=total+n;
   missing_total:=missing_total+missing_count;
   stale_total:=stale_total+stale_count;
   foreign_total:=foreign_total+foreign_count;
   unrelated_total:=unrelated_total+unrelated_count;
   orphan_total:=orphan_total+orphan_count;
   per_family:=per_family||jsonb_build_array(jsonb_build_object(
     'source_table',child_table,'parent_table',parent_table,
     'source_rows_checked',n,
     'missing_vault_snapshots',missing_count,
     'stale_vault_snapshots',stale_count,
     'foreign_contributions',foreign_count,
     'invalid_parent_child_associations',unrelated_count,
     'orphan_vault_snapshots',orphan_count,
     'mirror_consistent',missing_count=0 and stale_count=0 and
       foreign_count=0 and unrelated_count=0 and orphan_count=0));
 end loop;
 return jsonb_build_object(
   'schema','onespace.qa.private-child-mirror-preflight.v1',
   'owner_id',me,'source_space_id',sid,
   'mirrored_child_types_checked',array_length(tables,1),
   'child_source_rows_checked',total,
   'missing_child_vault_snapshots',missing_total,
   'stale_child_vault_snapshots',stale_total,
   'foreign_authored_or_recipient_children',foreign_total,
   'invalid_child_associations',unrelated_total,
   'orphan_child_vault_snapshots',orphan_total,
   'per_child_family',per_family,
   'supported_child_mirrors_consistent',
       missing_total=0 and stale_total=0 and foreign_total=0 and
       unrelated_total=0 and orphan_total=0,
   'all_archive_children_verified',false,
   'safe_to_archive',false,'safe_to_separate',false);
end $fn$;
revoke all on function private.qa_private_archive_child_mirror_preflight()
 from public,anon,authenticated;
grant execute on function private.qa_private_archive_child_mirror_preflight()
 to authenticated;

-- Keep one authenticated read-only public preflight that includes the nine
-- dependent families and the 14 private root mirror families, together with
-- explicit warnings about unsupported types.
create or replace function public.qa_private_archive_completeness_preflight()
returns jsonb language sql stable security invoker set search_path='' as $fn$
 select private.qa_private_archive_completeness_preflight() ||
   jsonb_build_object('mirrored_children',
     private.qa_private_archive_child_mirror_preflight())
$fn$;
revoke all on function public.qa_private_archive_completeness_preflight()
 from public,anon;
grant execute on function public.qa_private_archive_completeness_preflight()
 to authenticated;
