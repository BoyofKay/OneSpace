-- QA rollback-only regression for private task checklist ownership/mirroring.
begin;
do $qa$
declare
  sid uuid; owner_user uuid; partner_user uuid;
  task_uuid uuid; item_uuid uuid; check_uuid uuid;
  n integer; err text; snap jsonb;
begin
  select s.id,s.created_by,m.user_id into sid,owner_user,partner_user
    from public.spaces s join public.space_members m
      on m.space_id=s.id and m.user_id<>s.created_by
   where (select count(*) from public.space_members k where k.space_id=s.id)=2
   limit 1;
  if sid is null then raise exception 'Paired QA test fixture missing';end if;
  insert into public.tasks(space_id,created_by,title,visibility,recurrence)
   values(sid,owner_user,'QA PRIVATE CHECKLIST PRESERVATION','private','weekly')
   returning id into task_uuid;
  insert into public.task_checklist_items(task_id,created_by,title)
   values(task_uuid,owner_user,'Remember the family birthday')
   returning id into item_uuid;
  insert into public.task_checklist_checks(item_id,cycle_date,user_id,completed)
   values(item_uuid,date '2026-11-20',owner_user,true)
   returning id into check_uuid;

  select count(*) into n from public.personal_vault_dependents v
    where v.owner_id=owner_user and v.parent_table='tasks'
      and v.parent_id=task_uuid and v.source_table in
        ('task_checklist_items','task_checklist_checks') and v.restorable;
  if n<>2 then raise exception 'Expected 2 private checklist snapshots: %',n;end if;
  if exists (select 1 from public.personal_vault_dependents
     where parent_id=task_uuid and owner_id=partner_user and restorable)
  then raise exception 'Partner received another user private checklist';end if;

  begin
    insert into public.task_checklist_items(task_id,created_by,title)
     values(task_uuid,partner_user,'Partner-owned item must not be private');
    raise exception 'Unexpected partner private checklist item accepted';
  exception when others then
    get stacked diagnostics err=message_text;
    if err<>'Private checklist child must belong to task owner' then
      raise exception 'Unexpected item ownership outcome: %',err;end if;
  end;
  begin
    insert into public.task_checklist_checks(item_id,cycle_date,user_id)
     values(item_uuid,date '2026-11-21',partner_user);
    raise exception 'Unexpected partner private checklist check accepted';
  exception when others then
    get stacked diagnostics err=message_text;
    if err<>'Private checklist child must belong to task owner' then
      raise exception 'Unexpected check ownership outcome: %',err;end if;
  end;

  update public.tasks set visibility='shared' where id=task_uuid;
  if exists(select 1 from public.personal_vault_dependents
      where parent_id=task_uuid and restorable) then
    raise exception 'Task became shared but private child snapshots remain';end if;
  update public.tasks set visibility='private' where id=task_uuid;
  select count(*) into n from public.personal_vault_dependents
      where parent_id=task_uuid and owner_id=owner_user and restorable;
  if n<>2 then raise exception 'Task returned private without child resync: %',n;end if;

  update public.task_checklist_items set title='Reminder: family birthday'
    where id=item_uuid;
  select snapshot into snap from public.personal_vault_dependents
   where source_table='task_checklist_items' and source_id=item_uuid
     and owner_id=owner_user;
  if snap->>'title'<>'Reminder: family birthday' then
    raise exception 'Checklist child edits not mirrored';end if;

  delete from public.task_checklist_checks where id=check_uuid;
  if exists(select 1 from public.personal_vault_dependents
     where source_table='task_checklist_checks' and source_id=check_uuid
       and restorable) then
    raise exception 'Deleted checklist check remains restorable';end if;

  if has_function_privilege('anon',
      'private.qa_sync_private_task_checklist(uuid)','execute')
     or has_function_privilege('authenticated',
      'private.qa_sync_private_task_checklist(uuid)','execute')
     or has_function_privilege('anon',
      'private.qa_mirror_private_task_child()','execute')
  then raise exception 'Private checklist vault helpers publicly callable';end if;
end $qa$;
rollback;
select 'PASS: checklist owner snapshots, edits, visibility transitions, foreign-author denial, delete tombstones, execution isolation; rolled back' as result;
