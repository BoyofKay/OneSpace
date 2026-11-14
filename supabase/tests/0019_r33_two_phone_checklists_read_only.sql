-- R33: read-only dual-account checklist page regression.
-- Uses existing membership for QA context; never changes tasks or checkmarks.
begin;
select set_config('qa.space',space_id::text,true)
 from public.space_members group by space_id having count(*)=2 limit 1;
select set_config('qa.a',user_id::text,true)
 from public.space_members where space_id=current_setting('qa.space')::uuid
 order by joined_at limit 1;
select set_config('qa.b',user_id::text,true)
 from public.space_members where space_id=current_setting('qa.space')::uuid
 order by joined_at desc limit 1;
set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('qa.a'),true);
do $check$
declare t int; i int; checks int;
begin
 select count(*) into t from public.tasks
 where space_id=current_setting('qa.space')::uuid
  and migrated_to_list is null;
 select count(*) into i from public.task_checklist_items x
  join public.tasks t on x.task_id=t.id
  where t.space_id=current_setting('qa.space')::uuid
   and t.migrated_to_list is null;
 select count(*) into checks from public.task_checklist_checks c
  join public.tasks t on c.task_id=t.id
  where t.space_id=current_setting('qa.space')::uuid;
 if t<1 or i<1 then raise exception
  'First partner cannot load visible task and subtask data';end if;
end $check$;
select set_config('request.jwt.claim.sub',current_setting('qa.b'),true);
do $check$
declare t int; i int; checks int;
begin
 select count(*) into t from public.tasks
 where space_id=current_setting('qa.space')::uuid
  and migrated_to_list is null;
 select count(*) into i from public.task_checklist_items x
  join public.tasks t on x.task_id=t.id
  where t.space_id=current_setting('qa.space')::uuid
   and t.migrated_to_list is null;
 select count(*) into checks from public.task_checklist_checks c
  join public.tasks t on c.task_id=t.id
  where t.space_id=current_setting('qa.space')::uuid;
 if t<1 or i<1 then raise exception
  'Second partner cannot load visible task and subtask data';end if;
end $check$;
select 'PASS: both existing accounts can query live checklist and subtask rows under RLS' as result;
rollback;