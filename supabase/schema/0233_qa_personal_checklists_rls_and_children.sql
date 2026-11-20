-- QA 0233: authenticated owner-owned tasks + checklist child boundaries.
-- Existing legacy rows and user membership are not changed.
CREATE OR REPLACE FUNCTION private.qa_mirror_private_task_child()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  child_id uuid;
  task_id uuid;
  child_actor uuid;
  old_actor uuid;
  old_task uuid;
  task_owner uuid;
  task_visibility text;
  task_space uuid;
  task_private_space uuid;
begin
  if tg_table_schema<>'public' or tg_table_name not in
     ('task_checklist_items','task_checklist_checks') then
    raise exception 'Unexpected checklist vault source';
  end if;
  if tg_op='DELETE' then
    if current_setting('onespace.retiring_space',true) is distinct from 'on' then
      update public.personal_vault_dependents set
        restorable=false,snapshot='{}'::jsonb,last_mirrored_at=now()
      where source_table=tg_table_name and source_id=old.id;
    end if;
    return old;
  end if;
  child_id:=new.id;
  if tg_table_name='task_checklist_items' then
    task_id:=new.task_id;
    child_actor:=new.created_by;
    if tg_op='UPDATE' then
      old_actor:=old.created_by;
      old_task:=old.task_id;
    end if;
  else
    task_id:=new.task_id;
    child_actor:=new.user_id;
    if tg_op='UPDATE' then
      old_actor:=old.user_id;
      old_task:=old.task_id;
    end if;
    -- A check's claimed task_id must be the actual item's task.
    if not exists (select 1 from public.task_checklist_items i
                   where i.id=new.item_id and i.task_id=new.task_id) then
      raise exception 'Checklist check and item task mismatch';
    end if;
  end if;

  if tg_op='UPDATE' and (old_actor is distinct from child_actor
                         or old_task is distinct from task_id) then
    update public.personal_vault_dependents set
      restorable=false,snapshot='{}'::jsonb,last_mirrored_at=now()
     where source_table=tg_table_name and source_id=child_id;
  end if;

  select t.created_by,t.visibility,t.space_id,t.private_space_id
    into task_owner,task_visibility,task_space,task_private_space
    from public.tasks t where t.id=task_id;
  if not found then raise exception 'Checklist task not found'; end if;
  -- New account-owned checklists require no retired archive mirror.
  if task_private_space is not null then
    if task_private_space is distinct from task_owner
       or task_visibility <> 'private'
       or child_actor is distinct from task_owner then
      raise exception 'Personal checklist child ownership mismatch';
    end if;
    return new;
  end if;
  if task_visibility='private' then
    if child_actor is distinct from task_owner then
      raise exception 'Private checklist child must belong to task owner';
    end if;
    if not exists (
      select 1 from public.personal_vault_records v
       where v.source_table='tasks' and v.source_id=task_id
         and v.owner_id=task_owner and v.source_space_id=task_space
         and v.current_visibility='private' and v.restorable
    ) then
      raise exception 'Private task root snapshot missing';
    end if;
    insert into public.personal_vault_dependents(
        owner_id,parent_table,parent_id,source_table,source_id,
        source_space_id,snapshot)
    values(task_owner,'tasks',task_id,tg_table_name,child_id,task_space,
           private.qa_structured_value(to_jsonb(new)))
    on conflict(owner_id,source_table,source_id) do update set
      parent_table=excluded.parent_table,parent_id=excluded.parent_id,
      source_space_id=excluded.source_space_id,snapshot=excluded.snapshot,
      restorable=true,last_mirrored_at=now();
  else
    -- Shared checklist participation is never portable as a private record.
    update public.personal_vault_dependents
       set restorable=false,snapshot='{}'::jsonb,last_mirrored_at=now()
     where source_table=tg_table_name and source_id=child_id;
  end if;
  return new;
end $function$
;
CREATE OR REPLACE FUNCTION private.qa_task_checklist_parent_changed()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if new.private_space_id is not null then
    if new.private_space_id is distinct from new.created_by or new.visibility <> 'private' then
      raise exception 'Personal checklist parent scope mismatch';
    end if;
    return new;
  end if;
  if old.created_by is distinct from new.created_by
      or old.space_id is distinct from new.space_id then
    update public.personal_vault_dependents
     set restorable=false,snapshot='{}'::jsonb,last_mirrored_at=now()
     where parent_table='tasks' and parent_id=new.id;
  end if;
  perform private.qa_sync_private_task_checklist(new.id);
  return new;
end $function$
;
alter table public.tasks drop constraint if exists qa_personal_task_no_partner_link;
alter table public.tasks add constraint qa_personal_task_no_partner_link
 check(private_space_id is null or (visibility='private' and assigned_to is null
  and trip_id is null and migrated_to_list is null)) not valid;
drop policy if exists "QA owner reads personal tasks" on public.tasks;
create policy "QA owner reads personal tasks" on public.tasks for select to authenticated
 using (private_space_id=(select auth.uid()) and created_by=(select auth.uid())
   and visibility='private' and space_id is null);
drop policy if exists "QA owner creates personal tasks" on public.tasks;
create policy "QA owner creates personal tasks" on public.tasks for insert to authenticated
 with check(private_space_id=(select auth.uid()) and created_by=(select auth.uid())
   and visibility='private' and space_id is null and assigned_to is null and trip_id is null);
drop policy if exists "QA owner edits personal tasks" on public.tasks;
create policy "QA owner edits personal tasks" on public.tasks for update to authenticated
 using(private_space_id=(select auth.uid()) and created_by=(select auth.uid())
   and visibility='private' and space_id is null)
 with check(private_space_id=(select auth.uid()) and created_by=(select auth.uid())
   and visibility='private' and space_id is null and assigned_to is null and trip_id is null);
drop policy if exists "QA shared task requires pair to create" on public.tasks;
create policy "QA shared task requires pair to create" on public.tasks as restrictive
 for insert to authenticated with check(visibility<>'shared' or
 (select count(*) from public.space_members m where m.space_id=tasks.space_id)=2);
drop policy if exists "QA shared task requires pair to update" on public.tasks;
create policy "QA shared task requires pair to update" on public.tasks as restrictive
 for update to authenticated using(true) with check(visibility<>'shared' or
 (select count(*) from public.space_members m where m.space_id=tasks.space_id)=2);
grant insert,update on public.tasks to authenticated;
grant insert,update on public.task_checklist_items to authenticated;
grant insert,update on public.task_checklist_checks to authenticated;
drop policy if exists "QA owner sees personal task audit" on public.record_action_history;
create policy "QA owner sees personal task audit" on public.record_action_history for select to authenticated
 using(record_kind='task' and private_space_id=(select auth.uid())
 and exists(select 1 from public.tasks t where t.id=record_id
 and t.private_space_id=(select auth.uid())
 and t.created_by=(select auth.uid()) and t.visibility='private'));
