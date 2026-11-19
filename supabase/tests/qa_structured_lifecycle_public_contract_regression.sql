begin;
do $test$
declare
  v_owner uuid;
  v_partner uuid;
  status jsonb;
  ready jsonb;
  preflight jsonb;
begin
  select sp.created_by,sm.user_id into v_owner,v_partner
  from public.spaces sp join public.space_members sm
    on sm.space_id=sp.id and sm.user_id<>sp.created_by
  where (select count(*) from public.space_members k where k.space_id=sp.id)=2
  limit 1;
  if v_owner is null then raise exception 'No QA owner/partner to test'; end if;
  if has_function_privilege('anon','public.space_lifecycle_readiness()','execute')
    or has_function_privilege('anon','public.space_separation_preflight()','execute')
    or has_function_privilege('anon','public.my_space_lifecycle_status()','execute') then
    raise exception 'Anonymous lifecycle detail must be blocked';
  end if;
  perform set_config('role','authenticated',true);
  for status in select public.my_space_lifecycle_status()
    from (values(v_owner),(v_partner)) as caller(id)
    where set_config('request.jwt.claim.sub',caller.id::text,true) is not null
  loop
    if status->>'media_included'<>'false'
      or status->>'documents_included'<>'false'
      or status->>'archive_policy'<>'structured_private_shared_no_media_v1'
      or status->>'safe_to_finalize'<>'false' then
      raise exception 'Old media-inclusive lifecycle policy leaked into public status: %',status;
    end if;
  end loop;
  perform set_config('request.jwt.claim.sub',v_owner::text,true);
  ready:=public.space_lifecycle_readiness();
  preflight:=public.space_separation_preflight();
  if ready->>'safe_to_separate'<>'false' or
    ready->>'media_included'<>'false' or
    ready ? 'private_root_records' or
    ready ? 'space_linked_records' or
    preflight<>ready then
    raise exception 'Public readiness leak or unsafe separation approval: %',ready;
  end if;
end $test$;
rollback;
select 'PASS: public lifecycle remains media-excluded and fail-closed; role and private counts protected' result;
