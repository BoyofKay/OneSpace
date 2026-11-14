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
insert into public.shared_trips(space_id,title,origin,destination,visibility,status)
 values(current_setting('qa.space')::uuid,'QA prep private R27','Riyadh','Philadelphia','private','planning'),
 (current_setting('qa.space')::uuid,'QA prep shared R27','Riyadh','Philadelphia','shared','planning');
select set_config('qa.private',(select id::text from public.shared_trips where title='QA prep private R27'),true);
select set_config('qa.shared',(select id::text from public.shared_trips where title='QA prep shared R27'),true);
select set_config('qa.task',public.create_trip_preparation_checklist(
 current_setting('qa.shared')::uuid,'travel_basics')::text,true);
do $t$ begin
 if public.create_trip_preparation_checklist(current_setting('qa.shared')::uuid,'travel_basics')
 <>current_setting('qa.task')::uuid then
 raise exception 'Repeated click created another checklist';end if;
 if (select count(*) from public.task_checklist_items
  where task_id=current_setting('qa.task')::uuid)<>8 then
 raise exception 'Travel checklist missing items';end if;
end $t$;
select set_config('request.jwt.claim.sub',current_setting('qa.b'),true);
do $t$
declare blocked boolean:=false;
begin
 if (select count(*) from public.tasks
 where id=current_setting('qa.task')::uuid)<>1 then
 raise exception 'Partner cannot see shared trip checklist';end if;
 begin
  perform public.create_trip_preparation_checklist(
   current_setting('qa.private')::uuid,'travel_basics');
 exception when others then blocked:=true;end;
 if not blocked then raise exception 'Private trip checklist leaked';end if;
end $t$;
select 'PASS: R27 travel checklist, idempotence and private trip access' result;
rollback;