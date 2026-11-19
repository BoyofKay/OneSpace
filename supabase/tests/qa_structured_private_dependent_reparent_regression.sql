-- QA: parent reassignment is captured, stale copy cannot be restored.
begin;
do $test$
declare
  sid uuid;
  v_owner uuid;
  v_partner uuid;
  plan_a uuid;
  plan_b uuid;
  child_id uuid;
  rel record;
  err text;
begin
  select sp.id,sp.created_by,sm.user_id into sid,v_owner,v_partner
  from public.spaces sp join public.space_members sm
    on sm.space_id=sp.id and sm.user_id<>sp.created_by
  where (select count(*) from public.space_members k where k.space_id=sp.id)=2
  limit 1;
  if sid is null then raise exception 'No QA paired space'; end if;

  insert into public.occasion_plans(space_id,created_by,title,occasion_on,visibility)
    values(sid,v_owner,'Temporary private plan A',current_date+7,'private')
    returning id into plan_a;
  insert into public.occasion_plans(space_id,created_by,title,occasion_on,visibility)
    values(sid,v_owner,'Temporary private plan B',current_date+14,'private')
    returning id into plan_b;
  insert into public.occasion_plan_steps(plan_id,created_by,title)
    values(plan_a,v_owner,'Temporary structured subtask')
    returning id into child_id;
  select parent_id,restorable,snapshot into rel from public.personal_vault_dependents
   where source_table='occasion_plan_steps' and source_id=child_id and owner_id=v_owner;
  if rel.parent_id is distinct from plan_a or not rel.restorable then
    raise exception 'Missing personal dependent snapshot';
  end if;

  update public.occasion_plan_steps set plan_id=plan_b where id=child_id;
  select parent_id,restorable into rel from public.personal_vault_dependents
   where source_table='occasion_plan_steps' and source_id=child_id and owner_id=v_owner;
  if rel.parent_id is distinct from plan_b or not rel.restorable then
    raise exception 'Reparented dependent still points to old private plan';
  end if;

  -- Moving a child to another owner must not leave the old owner a copy.
  update public.occasion_plan_steps set created_by=v_partner where id=child_id;
  select restorable,snapshot into rel from public.personal_vault_dependents
   where source_table='occasion_plan_steps' and source_id=child_id and owner_id=v_owner;
  if rel.restorable or rel.snapshot<>'{}'::jsonb then
    raise exception 'Previous owner retained a restorable child after owner changed';
  end if;

  -- Creating a private record on behalf of an unrelated member is rejected.
  begin
    insert into public.notes(space_id,created_by,title,body,visibility)
      select sid,u.id,'Unauthorized synthetic','No','private'
      from auth.users u
      where u.id not in (select sm.user_id from public.space_members sm where sm.space_id=sid)
      limit 1;
    if found then raise exception 'Private record allowed invalid relationship owner'; end if;
  exception when others then
    get stacked diagnostics err=message_text;
    if err not like 'Private record owner must be a space member%' then
      raise exception 'Unexpected private owner validation: %',err;
    end if;
  end;
end $test$;
rollback;
select 'PASS: parent reassignment, owner invalidation and cross-space author rejection; all rows rolled back' result;
