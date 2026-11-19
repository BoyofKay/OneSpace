-- QA: dependent ownership is a real relationship, not a stale FK snapshot.
-- Reparenting or changing the owner must invalidate previous vault ownership.
create or replace function private.mirror_personal_vault_dependent()
returns trigger language plpgsql security definer set search_path='' as $fn$
declare
  v_owner uuid;
  v_parent_type text;
  v_parent uuid;
  v_previous_owner uuid;
  v_previous_parent uuid;
begin
  if tg_table_name in ('occasion_budget_items','occasion_plan_steps','occasion_proposals') then
    v_owner:=new.created_by;
    v_parent_type:='occasion_plans';
    v_parent:=new.plan_id;
    if tg_op='UPDATE' then
      v_previous_owner:=old.created_by;
      v_previous_parent:=old.plan_id;
    end if;
  elsif tg_table_name='reminder_recipients' then
    v_owner:=new.recipient_id;
    v_parent_type:='reminders';
    v_parent:=new.reminder_id;
    if tg_op='UPDATE' then
      v_previous_owner:=old.recipient_id;
      v_previous_parent:=old.reminder_id;
    end if;
  else
    raise exception 'Unexpected private dependent source';
  end if;
  if tg_op='UPDATE' and
    (v_previous_owner is distinct from v_owner or v_previous_parent is distinct from v_parent)
    and v_previous_owner is not null then
    update public.personal_vault_dependents
       set restorable=false,snapshot='{}'::jsonb,last_mirrored_at=now()
     where owner_id=v_previous_owner and source_table=tg_table_name and source_id=old.id;
  end if;

  if v_owner is null then return new; end if;
  insert into public.personal_vault_dependents(
    owner_id,parent_table,parent_id,source_table,source_id,source_space_id,snapshot)
  select v_owner,v_parent_type,v_parent,tg_table_name,new.id,v.source_space_id,
         private.qa_structured_value(to_jsonb(new))
    from public.personal_vault_records v
   where v.owner_id=v_owner and v.source_table=v_parent_type
     and v.source_id=v_parent and v.restorable and v.current_visibility='private'
  on conflict(owner_id,source_table,source_id) do update set
    parent_table=excluded.parent_table,parent_id=excluded.parent_id,
    source_space_id=excluded.source_space_id,
    snapshot=excluded.snapshot,restorable=true,last_mirrored_at=now();
  return new;
end $fn$;
revoke all on function private.mirror_personal_vault_dependent() from public,anon,authenticated;

create or replace function private.mirror_personal_days_off()
returns trigger language plpgsql security definer set search_path='' as $fn$
begin
  if tg_op='UPDATE' and old.user_id is distinct from new.user_id then
    update public.personal_vault_records
      set restorable=false,current_visibility='ownership_changed',
          snapshot='{}'::jsonb,last_mirrored_at=now()
     where owner_id=old.user_id and source_table='personal_days_off'
       and source_id=old.id;
  end if;
  if new.user_id is null then return new; end if;
  if not exists(select 1 from public.space_members sm
      where sm.space_id=new.space_id and sm.user_id=new.user_id) then
    raise exception 'Personal day owner must belong to the space';
  end if;
  insert into public.personal_vault_records(
    owner_id,source_table,source_id,source_space_id,
    original_visibility,current_visibility,restorable,snapshot)
  values(new.user_id,'personal_days_off',new.id,new.space_id,
         'private','private',true,private.qa_structured_value(to_jsonb(new)))
  on conflict(owner_id,source_table,source_id) do update set
    source_space_id=excluded.source_space_id,snapshot=excluded.snapshot,
    current_visibility='private',restorable=true,last_mirrored_at=now();
  return new;
end $fn$;
revoke all on function private.mirror_personal_days_off() from public,anon,authenticated;
