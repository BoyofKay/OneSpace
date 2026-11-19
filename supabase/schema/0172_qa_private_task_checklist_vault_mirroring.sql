-- QA 0172: preserve owner-only checklist items + completion checks.
-- The separate Personal Vault shadows current private source data; it does not
-- enable portable archive or restoration, and does not modify Production.
create or replace function private.qa_mirror_private_task_child()
returns trigger language plpgsql security definer set search_path='' as $fn$
declare
  child_id uuid;
  task_id uuid;
  child_actor uuid;
  old_actor uuid;
  old_task uuid;
  task_owner uuid;
  task_visibility text;
  task_space uuid;
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

  select t.created_by,t.visibility,t.space_id
    into task_owner,task_visibility,task_space
    from public.tasks t where t.id=task_id;
  if not found then raise exception 'Checklist task not found'; end if;
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
end $fn$;
revoke all on function private.qa_mirror_private_task_child()
  from public,anon,authenticated;

create or replace function private.qa_sync_private_task_checklist(p_task_id uuid)
returns void language plpgsql security definer set search_path='' as $fn$
declare
  root public.tasks%rowtype;
begin
  select * into root from public.tasks where id=p_task_id;
  if not found then return; end if;
  if root.visibility<>'private' then
    update public.personal_vault_dependents
      set restorable=false,snapshot='{}'::jsonb,last_mirrored_at=now()
    where parent_table='tasks' and parent_id=root.id;
    return;
  end if;
  if not exists (
    select 1 from public.personal_vault_records v
    where v.owner_id=root.created_by and v.source_table='tasks'
      and v.source_id=root.id and v.source_space_id=root.space_id
      and v.current_visibility='private' and v.restorable
  ) then raise exception 'Private task root vault missing';end if;
  -- Records from another member, possibly authored while shared, are never
  -- silently copied to the new private owner's vault. The future exporter
  -- must fail closed until that ownership conflict is separately resolved.
  insert into public.personal_vault_dependents(
     owner_id,parent_table,parent_id,source_table,source_id,
     source_space_id,snapshot)
  select root.created_by,'tasks',root.id,'task_checklist_items',i.id,
         root.space_id,private.qa_structured_value(to_jsonb(i))
    from public.task_checklist_items i
   where i.task_id=root.id and i.created_by=root.created_by
  on conflict(owner_id,source_table,source_id) do update set
    parent_table=excluded.parent_table,parent_id=excluded.parent_id,
    source_space_id=excluded.source_space_id,snapshot=excluded.snapshot,
    restorable=true,last_mirrored_at=now();

  insert into public.personal_vault_dependents(
     owner_id,parent_table,parent_id,source_table,source_id,
     source_space_id,snapshot)
  select root.created_by,'tasks',root.id,'task_checklist_checks',c.id,
         root.space_id,private.qa_structured_value(to_jsonb(c))
    from public.task_checklist_checks c
    join public.task_checklist_items i on i.id=c.item_id
   where i.task_id=root.id and c.task_id=root.id
     and c.user_id=root.created_by
  on conflict(owner_id,source_table,source_id) do update set
    parent_table=excluded.parent_table,parent_id=excluded.parent_id,
    source_space_id=excluded.source_space_id,snapshot=excluded.snapshot,
    restorable=true,last_mirrored_at=now();
end $fn$;
revoke all on function private.qa_sync_private_task_checklist(uuid)
  from public,anon,authenticated;

create or replace function private.qa_task_checklist_parent_changed()
returns trigger language plpgsql security definer set search_path='' as $fn$
begin
  if old.created_by is distinct from new.created_by
      or old.space_id is distinct from new.space_id then
    update public.personal_vault_dependents
     set restorable=false,snapshot='{}'::jsonb,last_mirrored_at=now()
     where parent_table='tasks' and parent_id=new.id;
  end if;
  perform private.qa_sync_private_task_checklist(new.id);
  return new;
end $fn$;
revoke all on function private.qa_task_checklist_parent_changed()
  from public,anon,authenticated;

create trigger qa_task_checklist_parent_changed
  after update of visibility,created_by,space_id on public.tasks
  for each row execute function private.qa_task_checklist_parent_changed();
create trigger qa_task_checklist_mirror
  after insert or update or delete on public.task_checklist_items
  for each row execute function private.qa_mirror_private_task_child();
create trigger qa_task_checklist_mirror
  after insert or update or delete on public.task_checklist_checks
  for each row execute function private.qa_mirror_private_task_child();

-- QA only: seed shadow copies for any existing private tasks, no root content changed.
do $backfill$
declare rec record;
begin
 for rec in select id from public.tasks where visibility='private' loop
   perform private.qa_sync_private_task_checklist(rec.id);
 end loop;
end $backfill$;
