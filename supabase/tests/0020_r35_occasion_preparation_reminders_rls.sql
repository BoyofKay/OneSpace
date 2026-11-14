-- R35 non-destructive, two-account validation in a transaction.
-- All sample occasions, reminders and any server-created recipients roll back.
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
insert into public.occasion_plans(space_id,title,occasion_on,visibility)
 values(current_setting('qa.space')::uuid,'R35 shared QA',date '2026-12-25','shared');
insert into public.occasion_plans(space_id,title,occasion_on,visibility)
 values(current_setting('qa.space')::uuid,'R35 private QA',date '2026-12-25','private');
select set_config('qa.shared',(select id::text from public.occasion_plans
 where title='R35 shared QA' limit 1),true);
select set_config('qa.private',(select id::text from public.occasion_plans
 where title='R35 private QA' limit 1),true);

insert into public.reminders(space_id,title,due_at,visibility,audience,
 source_kind,source_id,planning_phase,occasion_instance_on)
 values(current_setting('qa.space')::uuid,'R35 saving private',
 now()+interval '1 day','private','me','occasion',
 current_setting('qa.shared')::uuid,'save',date '2026-12-25');

do $r35$
declare denied boolean:=false;
begin
 begin
  insert into public.reminders(space_id,title,due_at,visibility,audience,
   source_kind,source_id,planning_phase,occasion_instance_on)
  values(current_setting('qa.space')::uuid,'Duplicate phase',
   now()+interval '2 days','private','me','occasion',
   current_setting('qa.shared')::uuid,'save',date '2026-12-25');
 exception when unique_violation then denied:=true;end;
 if not denied then raise exception 'Duplicate phase allowed';end if;
end $r35$;

-- Annual occurrence is distinct, so next year's preparation is possible.
insert into public.reminders(space_id,title,due_at,visibility,audience,
 source_kind,source_id,planning_phase,occasion_instance_on)
 values(current_setting('qa.space')::uuid,'Next year saving',
 now()+interval '300 days','private','me','occasion',
 current_setting('qa.shared')::uuid,'save',date '2027-12-25');

-- Private occasion cannot become visible via a shared linked reminder.
do $r35$
declare denied boolean:=false;
begin
 begin
  insert into public.reminders(space_id,title,due_at,visibility,audience,
   source_kind,source_id,planning_phase,occasion_instance_on)
  values(current_setting('qa.space')::uuid,'Unsafe reveal',
   now()+interval '1 day','shared','both','occasion',
   current_setting('qa.private')::uuid,'research',date '2026-12-25');
 exception when others then denied:=true;end;
 if not denied then raise exception 'Private surprise leaked';end if;
end $r35$;

select set_config('request.jwt.claim.sub',current_setting('qa.b'),true);
do $r35$
begin
 if exists (select 1 from public.reminders where title='R35 saving private')
 then raise exception 'Second partner sees private reminder';end if;
 if not exists (select 1 from public.occasion_plans where id=
  current_setting('qa.shared')::uuid) then
   raise exception 'Second partner cannot see shared occasion';end if;
end $r35$;
insert into public.reminders(space_id,title,due_at,visibility,audience,
 source_kind,source_id,planning_phase,occasion_instance_on)
 values(current_setting('qa.space')::uuid,'Second partner independent',
 now()+interval '1 day','private','me','occasion',
 current_setting('qa.shared')::uuid,'save',date '2026-12-25');
select 'PASS: R35 duplicate guard, next year planning, private source, and partner RLS' as result;
rollback;
