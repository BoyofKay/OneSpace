-- QA rollback-only regression: only original owner can package private data;
-- service staging is separate from real archives and cannot enable restore.
begin;
do $qa$
declare sid uuid; a uuid; b uuid; tid uuid; pkg jsonb;
  reserve jsonb; rid uuid; n integer; message text;
begin
  select s.id,s.created_by,m.user_id into sid,a,b
   from public.spaces s join public.space_members m
     on m.space_id=s.id and m.user_id<>s.created_by
   where (select count(*) from public.space_members x where x.space_id=s.id)=2
   limit 1;
  if sid is null then raise exception 'Paired QA fixture unavailable';end if;

  insert into public.tasks(space_id,created_by,title,visibility)
    values(sid,a,'QA ENCRYPTED PREVIEW TASK','private')
    returning id into tid;
  insert into public.task_checklist_items(task_id,created_by,title)
    values(tid,a,'Keep this private task checklist');

  if has_function_privilege('anon',
       'public.qa_private_structured_package(text,uuid)','execute')
     or has_function_privilege('anon',
       'public.qa_preview_reserve_service(uuid,uuid,text,uuid)','execute')
     or has_function_privilege('authenticated',
       'public.qa_preview_mark_available_service(uuid,text,integer)','execute')
  then raise exception 'Anonymous/user privilege on preview service functions';end if;

  perform set_config('role','authenticated',true);
  perform set_config('request.jwt.claim.sub',a::text,true);
  pkg:=public.qa_private_structured_package('tasks',tid);
  if pkg#>>'{payload,owner_id}'<>a::text
    or pkg#>>'{payload,root,source_id}'<>tid::text
    or pkg#>>'{payload,child_record_count}'<>'1'
    or pkg->>'is_verified_archive'<>'false'
  then raise exception 'Invalid owner private preview response';end if;
  begin
    perform public.qa_preview_reserve_service(a,sid,'tasks',tid);
    raise exception 'User directly reserved preview Storage slot';
  exception when others then
    get stacked diagnostics message=message_text;
    if message<>'permission denied for function qa_preview_reserve_service'
       and message<>'Service role only' then
      raise exception 'Unexpected reservation exposure: %',message;
    end if;
  end;
  perform set_config('request.jwt.claim.sub',b::text,true);
  begin
    perform public.qa_private_structured_package('tasks',tid);
    raise exception 'Partner accessed owner private task';
  exception when others then
    get stacked diagnostics message=message_text;
    if message<>'Private task not found' then
      raise exception 'Wrong partner failure: %',message;end if;
  end;

  perform set_config('role','service_role',true);
  reserve:=public.qa_preview_reserve_service(a,sid,'tasks',tid);
  rid:=(reserve->>'preview_id')::uuid;
  if reserve->>'object_path' not like a::text||'/qa-previews/%' then
    raise exception 'Incorrect owner-scoped encrypted object path';end if;
  if exists(select 1 from public.qa_structured_preview_staging
    where id=rid and (status<>'pending' or can_restore
      or is_verified_archive or safe_to_separate or verified_storage_bytes)) then
     raise exception 'Preview staging was wrongly considered complete';end if;
  if exists(select 1 from public.space_archives where id=rid) then
     raise exception 'Preview staging was conflated with lifecycle archive';end if;
  begin
    perform public.qa_preview_mark_available_service(rid,'bad hash',100);
    raise exception 'Invalid preview metadata accepted';
  exception when others then
    get stacked diagnostics message=message_text;
    if message<>'Invalid verified preview bytes' then
      raise exception 'Wrong invalid-hash error: %',message;end if;
  end;
  if not public.qa_preview_mark_available_service(rid,repeat('a',64),1024) then
    raise exception 'Service could not commit separately verified bytes';end if;
  if not exists(select 1 from public.qa_structured_preview_staging
    where id=rid and status='available' and verified_storage_bytes
      and is_verified_archive=false and can_restore=false
      and safe_to_separate=false) then
      raise exception 'Preview registry could enable lifecycle wrongly';end if;
  perform set_config('role','authenticated',true);
  perform set_config('request.jwt.claim.sub',b::text,true);
  select count(*) into n from public.qa_structured_preview_staging
     where id=rid;
  if n<>0 then raise exception 'Partner saw private encrypted staging metadata';end if;
  perform set_config('request.jwt.claim.sub',a::text,true);
  select count(*) into n from public.qa_structured_preview_staging
     where id=rid;
  if n<>1 then raise exception 'Owner cannot view own encrypted preview metadata';end if;

  perform set_config('role','service_role',true);
  for n in 1..4 loop
    perform public.qa_preview_reserve_service(a,sid,'tasks',tid);
  end loop;
  begin
    perform public.qa_preview_reserve_service(a,sid,'tasks',tid);
    raise exception 'Preview quota allowed sixth file within 24h';
  exception when others then
    get stacked diagnostics message=message_text;
    if message<>'QA preview limit reached (5 per 24 hours)' then
      raise exception 'Wrong QA rate-limit error: %',message;end if;
  end;
end $qa$;
rollback;
select 'PASS: owner-only package, segregated nonrestorable encrypted staging, recipient RLS, service-only write/finalize, metadata checks and 5/day cap; rolled back' result;
