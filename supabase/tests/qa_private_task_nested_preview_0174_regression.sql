-- QA transaction regression: both members, child integrity, share/privatize,
-- owner/partner scope, corrupted-vault denial and cross-author child denial.
begin;
do $qa$
declare
  sid uuid; a uuid; b uuid; task_id uuid; item_id uuid; check_id uuid;
  p jsonb; p2 jsonb; err text;
begin
  select s.id,s.created_by,m.user_id into sid,a,b
   from public.spaces s join public.space_members m
     on m.space_id=s.id and m.user_id<>s.created_by
   where (select count(*) from public.space_members sm where sm.space_id=s.id)=2
   limit 1;
  if sid is null then raise exception 'Paired QA fixture required';end if;
  if has_function_privilege('anon',
      'private.qa_private_task_checklist_package(uuid)','execute') then
    raise exception 'Anonymous private checklist preview is executable';end if;

  insert into public.tasks(space_id,created_by,title,visibility)
   values(sid,a,'QA CHECKLIST PACKAGE OWNERSHIP','private')
   returning id into task_id;
  insert into public.task_checklist_items(task_id,created_by,title)
   values(task_id,a,'First private task item')
   returning id into item_id;
  insert into public.task_checklist_checks(item_id,cycle_date,user_id,completed)
   values(item_id,date '2026-11-20',a,true)
   returning id into check_id;
  perform set_config('role','authenticated',true);
  perform set_config('request.jwt.claim.sub',a::text,true);
  p:=private.qa_private_task_checklist_package(task_id);
  if p#>>'{payload,schema}'<>'onespace.private-task-checklist-preview.v1'
   or p#>>'{payload,owner_id}'<>a::text
   or p#>>'{payload,child_record_count}'<>'2'
   or jsonb_array_length(p#>'{payload,children,task_checklist_items}')<>1
   or jsonb_array_length(p#>'{payload,children,task_checklist_checks}')<>1
   or p->>'encrypted'<>'false' or p->>'can_restore'<>'false'
   or p->>'safe_to_separate'<>'false'
   or p::text not like '%First private task item%'
  then raise exception 'Private checklist package manifest incomplete: %',p;end if;
  if p->>'payload_sha256'<>
      encode(extensions.digest(convert_to((p->'payload')::text,'UTF8'),'sha256'),'hex') then
    raise exception 'Checklist payload checksum mismatch';end if;
  p2:=private.qa_private_task_checklist_package(task_id);
  if p->>'payload_sha256'<>p2->>'payload_sha256' then
    raise exception 'Unchanged checklist payload hash unstable';end if;

  perform set_config('request.jwt.claim.sub',b::text,true);
  begin
    perform private.qa_private_task_checklist_package(task_id);
    raise exception 'Partner accessed private checklist package';
  exception when others then
    get stacked diagnostics err=message_text;
    if err<>'Private task not found' then
      raise exception 'Wrong partner denial: %',err;end if;
  end;

  perform set_config('role','postgres',true);
  update public.tasks set visibility='shared' where id=task_id;
  perform set_config('role','authenticated',true);
  perform set_config('request.jwt.claim.sub',a::text,true);
  begin
    perform private.qa_private_task_checklist_package(task_id);
    raise exception 'Shared checklist unexpectedly passed private preview';
  exception when others then
    get stacked diagnostics err=message_text;
    if err<>'Private task not found' then
      raise exception 'Wrong shared denial: %',err;end if;
  end;

  perform set_config('role','postgres',true);
  update public.tasks set visibility='private' where id=task_id;
  perform set_config('role','authenticated',true);
  p2:=private.qa_private_task_checklist_package(task_id);
  if p2#>>'{payload,child_record_count}'<>'2' then
    raise exception 'Checklist root re-private did not resync child vault';end if;

  perform set_config('role','postgres',true);
  update public.personal_vault_dependents set snapshot='{}'::jsonb
   where owner_id=a and source_table='task_checklist_checks'
     and source_id=check_id;
  perform set_config('role','authenticated',true);
  begin
    perform private.qa_private_task_checklist_package(task_id);
    raise exception 'Tampered checklist child snapshot accepted';
  exception when others then
    get stacked diagnostics err=message_text;
    if err<>'Private checklist check ownership or snapshot mismatch' then
      raise exception 'Wrong tamper denial: %',err;end if;
  end;
  perform set_config('role','postgres',true);
  update public.personal_vault_dependents
   set snapshot=private.qa_structured_value(to_jsonb(c))
   from public.task_checklist_checks c
   where source_table='task_checklist_checks' and source_id=check_id
     and c.id=check_id and owner_id=a;

  -- A partner might have contributed while the task was shared.
  -- In that case the original partner's row MUST NEVER be quietly claimed.
  update public.tasks set visibility='shared' where id=task_id;
  insert into public.task_checklist_items(task_id,created_by,title)
   values(task_id,b,'Partner contribution to formerly shared checklist');
  update public.tasks set visibility='private' where id=task_id;
  perform set_config('role','authenticated',true);
  begin
    perform private.qa_private_task_checklist_package(task_id);
    raise exception 'Partner-authored checklist item was silently absorbed';
  exception when others then
    get stacked diagnostics err=message_text;
    if err<>'Private checklist item ownership or snapshot mismatch' then
      raise exception 'Wrong foreign-author denial: %',err;end if;
  end;
end $qa$;
rollback;
select 'PASS: nested checklist hash, owner-only scope, shared/private transitions, tamper denial, foreign-author rejection; transaction rolled back' result;
