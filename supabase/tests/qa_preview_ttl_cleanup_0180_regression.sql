-- QA rollback-only TTL regression for segregated preview-object janitor.
begin;
do $test$
declare
  owner uuid; pid uuid:=gen_random_uuid(); future_id uuid:=gen_random_uuid();
  due_count integer; caller_count integer; err text;
begin
 select sm.user_id into owner from public.space_members sm limit 1;
 if owner is null then raise exception 'QA account fixture missing';end if;
 if has_function_privilege('authenticated',
    'public.qa_previews_due_for_purge_service()','execute')
   or has_function_privilege('anon',
    'public.qa_preview_finish_purge_service(uuid)','execute') then
   raise exception 'Client can execute cleanup functions';end if;
 insert into public.qa_structured_preview_staging(
    id,recipient_id,source_space_id,source_table,source_id,
    status,object_path,created_at,expires_at)
 values(pid,owner,gen_random_uuid(),'tasks',gen_random_uuid(),
    'pending',owner::text||'/qa-previews/'||pid::text||'.onespace-preview',
    now()-interval '2 days',now()-interval '1 day');
 insert into public.qa_structured_preview_staging(
    id,recipient_id,source_space_id,source_table,source_id,
    status,object_path,created_at,expires_at)
 values(future_id,owner,gen_random_uuid(),'tasks',gen_random_uuid(),
    'pending',owner::text||'/qa-previews/'||future_id::text||'.onespace-preview',
    now(),now()+interval '24 hours');

 perform set_config('role','service_role',true);
 select count(*) into due_count from public.qa_previews_due_for_purge_service()
  where preview_id in (pid,future_id);
 if due_count<>1 then raise exception 'Expected precisely one expired preview';end if;
 if not public.qa_preview_finish_purge_service(pid) then
   raise exception 'Service cannot record successful preview purge';end if;
 if public.qa_preview_finish_purge_service(future_id) then
   raise exception 'Service purged preview before TTL';end if;
 if exists(select 1 from public.qa_structured_preview_staging
   where id=pid and status<>'purged')
   or exists(select 1 from public.qa_structured_preview_staging
   where id=future_id and status<>'pending') then
   raise exception 'Preview janitor mutated unexpected status';end if;
 if (select count(*) from public.qa_previews_due_for_purge_service()
     where preview_id=pid)<>0 then
   raise exception 'Already-purged preview reappeared in due list';end if;
 perform set_config('role','authenticated',true);
 perform set_config('request.jwt.claim.sub',owner::text,true);
 select count(*) into caller_count from public.qa_structured_preview_staging
   where id in (pid,future_id);
 if caller_count<>2 then raise exception 'Owner lost preview metadata unexpectedly';end if;
 begin
   perform public.qa_previews_due_for_purge_service();
   raise exception 'Authenticated caller accessed janitor service';
 exception when others then
   get stacked diagnostics err=message_text;
   if err not in ('permission denied for function qa_previews_due_for_purge_service',
                  'Service role only') then
     raise exception 'Unexpected janitor authorization error: %',err;end if;
 end;
end $test$;
rollback;
select 'PASS: expired-only QA preview TTL, service-only purge, owner RLS, no premature deletion and rollback' result;
