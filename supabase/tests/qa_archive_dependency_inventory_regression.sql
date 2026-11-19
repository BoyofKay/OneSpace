-- QA only: transactionally verify FK-dependent archive inventory.
-- This script deliberately creates synthetic content and rolls it back.
begin;
do $test$
declare
  pair_space uuid := '7f26214b-0716-4c4f-9130-83905f1492c1';
  pair_owner uuid := 'fe29186f-8eb7-4d76-9c40-2d113f921cd7';
  other_owner uuid := '937e362d-6457-4fe2-b8cd-abad7157a015';
  activity_id uuid;
  me jsonb;
  other jsonb;
  client jsonb;
  readiness jsonb;
  actual bigint;
begin
  if has_function_privilege('anon','public.space_archive_dependency_inventory()','execute') then
    raise exception 'Anon must not execute dependency inventory';
  end if;
  if not exists(select 1 from public.space_members where space_id=pair_space and user_id=pair_owner)
    or not exists(select 1 from public.space_members where user_id=other_owner) then
    raise exception 'Missing QA-only test identities';
  end if;
  insert into public.activities(space_id,created_by,title,visibility)
  values(pair_space,pair_owner,'Temporary FK archive test','private')
  returning id into activity_id;
  insert into public.activity_comments(activity_id,author_id,body)
  values(activity_id,pair_owner,'Temporary FK comment');
  perform set_config('role','authenticated',true);
  perform set_config('request.jwt.claim.sub',pair_owner::text,true);
  me:=private.space_archive_dependency_inventory();
  client:=public.space_archive_dependency_inventory();
  readiness:=public.space_separation_preflight();
  if client ? 'details' or client ? 'linked_dependents' or
     readiness ? 'private_root_records' or readiness ? 'space_linked_records'
     or readiness ? 'unclassified_root_records' then
     raise exception 'Partner private-record counts exposed by public readiness API';
  end if;
  select (e->>'records')::bigint into actual
  from jsonb_array_elements(me->'details') e where e->>'table'='activity_comments';
  if actual is distinct from 1 then
    raise exception 'Nested comment count incorrect: %', actual;
  end if;
  if (me->>'dependent_tables_inspected')::int < 30
    or me->>'safe_to_export' <> 'false' then
    raise exception 'Missing dependent table coverage or unsafe export gate: %',me;
  end if;
  perform set_config('request.jwt.claim.sub',other_owner::text,true);
  other:=private.space_archive_dependency_inventory();
  select (e->>'records')::bigint into actual
    from jsonb_array_elements(other->'details') e where e->>'table'='activity_comments';
  if actual is distinct from 0 then
    raise exception 'Cross-space dependent records leaked: %', actual;
  end if;
end $test$;
rollback;
select 'PASS: nested FK coverage, cross-space isolation, privacy-safe public RPC, anon block, synthetic rows rolled back' as result;
