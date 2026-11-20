-- QA 0230: first account-owned content cutover: Notes.
-- Existing rows untouched; old app legacy writes still valid.
CREATE OR REPLACE FUNCTION private.capture_record_action()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 before jsonb;
 after jsonb;
 fields text[];
 action_name text;
 kind text;
begin
 kind:=case tg_table_name
  when 'notes' then 'note'
  when 'tasks' then 'task'
  when 'goals' then 'goal'
  when 'memories' then 'memory'
  when 'space_events' then 'event'
  when 'reminders' then 'reminder'
  when 'occasion_plans' then 'occasion'
  when 'shared_experiences' then 'experience'
  else null end;
 if kind is null then raise exception 'Unsupported audited table';end if;
 after:=to_jsonb(new);
 if tg_op='INSERT' then
  action_name:='created';
  select coalesce(array_agg(key order by key),'{}'::text[]) into fields
   from jsonb_object_keys(after) as k(key)
   where key not in ('updated_at','created_at','id','space_id','created_by');
 else
  before:=to_jsonb(old);
  select coalesce(array_agg(key order by key),'{}'::text[]) into fields
   from jsonb_object_keys(after) as k(key)
   where (after->key) is distinct from (before->key)
    and key not in ('updated_at','created_at');
  if cardinality(fields)=0 then return new;end if;
  action_name:=case
   when before->>'archived_at' is null and
    after->>'archived_at' is not null then 'archived'
   when before->>'archived_at' is not null and
    after->>'archived_at' is null then 'restored'
   when kind='task' and before->>'status'<>'cancelled' and
    after->>'status'='cancelled' then 'cancelled'
   when kind='task' and before->>'status'='cancelled' and
    after->>'status'<>'cancelled' then 'reopened'
   when (before->>'status') is distinct from (after->>'status') and (after->>'status') in ('completed','celebrated','enjoyed','booked') then 'completed' when (before->>'status') is distinct from (after->>'status') and (after->>'status')='cancelled' then 'cancelled' else 'edited' end;
 end if;
 insert into public.record_action_history(
  space_id,private_space_id,record_kind,record_id,actor_id,action,changed_fields)
 values ((after->>'space_id')::uuid,(after->>'private_space_id')::uuid,
  kind,(after->>'id')::uuid,auth.uid(),action_name,fields);
 return new;
end;
$function$
;
CREATE OR REPLACE FUNCTION private.mirror_personal_vault_record()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if tg_table_schema<>'public' or tg_table_name not in
    ('activities','daily_checkins','goals','items_to_sort','memories',
     'notes','occasion_plans','places','reminders','saved_contacts',
     'shared_trips','space_counters','space_events','tasks') then
    raise exception 'Unexpected vault source';
  end if;
  if tg_op='UPDATE' and old.visibility='private'
    and (old.created_by is distinct from new.created_by
         or new.visibility is distinct from 'private') then
    update public.personal_vault_records
       set current_visibility=case when new.visibility='private'
                                  then 'ownership_changed' else new.visibility end,
           restorable=false,snapshot='{}'::jsonb,last_mirrored_at=now()
     where owner_id=old.created_by and source_table=tg_table_name and source_id=old.id;
  end if;
  if new.visibility<>'private' or new.created_by is null then return new; end if;
  -- New personal records are source of truth; never mirror into obsolete vault.
  if new.private_space_id is not null then
    if new.private_space_id is distinct from new.created_by
       or new.space_id is not null then
      raise exception 'Private owner/scope mismatch';
    end if;
    return new;
  end if;
  if not exists(select 1 from public.space_members sm
    where sm.space_id=new.space_id and sm.user_id=new.created_by) then
    raise exception 'Private record owner must be a space member';
  end if;
  insert into public.personal_vault_records
    (owner_id,source_table,source_id,source_space_id,
     original_visibility,current_visibility,restorable,snapshot)
  values(new.created_by,tg_table_name,new.id,new.space_id,
         'private','private',true,private.qa_structured_value(to_jsonb(new)))
  on conflict(owner_id,source_table,source_id) do update set
    source_space_id=excluded.source_space_id,
    current_visibility='private',restorable=true,
    snapshot=excluded.snapshot,last_mirrored_at=now();
  return new;
end $function$
;

drop policy if exists "QA owner reads personal notes" on public.notes;
create policy "QA owner reads personal notes" on public.notes
 for select to authenticated
 using (private_space_id=(select auth.uid()) and created_by=(select auth.uid())
   and visibility='private' and space_id is null);
drop policy if exists "QA owner creates personal notes" on public.notes;
create policy "QA owner creates personal notes" on public.notes
 for insert to authenticated
 with check (private_space_id=(select auth.uid()) and created_by=(select auth.uid())
   and visibility='private' and space_id is null);
drop policy if exists "QA owner edits personal notes" on public.notes;
create policy "QA owner edits personal notes" on public.notes
 for update to authenticated
 using (private_space_id=(select auth.uid()) and created_by=(select auth.uid())
   and visibility='private' and space_id is null)
 with check (private_space_id=(select auth.uid()) and created_by=(select auth.uid())
   and visibility='private' and space_id is null);
-- Include new personal note audit history without exposing any other user's rows.
drop policy if exists "QA view my personal note audit history" on public.record_action_history;
create policy "QA view my personal note audit history" on public.record_action_history
 for select to authenticated
 using (
  record_kind='note'
  and private_space_id=(select auth.uid())
  and exists(select 1 from public.notes n where n.id=record_id
    and n.private_space_id=(select auth.uid())
    and n.visibility='private'
    and n.created_by=(select auth.uid()))
 );

-- All 0228 exactly-one-scope and creator checks remain enforced.
-- This migration does NOT enable relationship/account deletion or change memberships.
