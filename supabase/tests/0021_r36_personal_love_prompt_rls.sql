-- R36: rollback-only partner privacy and non-automatic love reminder guard.
begin;
select set_config('qa.space',space_id::text,true)
 from public.space_members group by space_id having count(*)=2 limit 1;
select set_config('qa.a',user_id::text,true)
 from public.space_members where space_id=current_setting('qa.space')::uuid
 order by joined_at limit 1;
select set_config('qa.b',user_id::text,true)
 from public.space_members where space_id=current_setting('qa.space')::uuid
 order by joined_at desc limit 1;
select set_config('qa.due',(now()+interval '1 day')::text,true);
set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('qa.a'),true);
insert into public.reminders(space_id,title,due_at,visibility,audience,
 reminder_intent,reminder_gesture_kind)
 values(current_setting('qa.space')::uuid,'R36 send love privately',
 current_setting('qa.due')::timestamptz,'private','me','love_gesture','any');
do $r36$
declare rejected boolean:=false;
begin
 begin
  insert into public.reminders(space_id,title,due_at,visibility,audience,
   reminder_intent,reminder_gesture_kind)
   values(current_setting('qa.space')::uuid,'R36 same prompt',
   current_setting('qa.due')::timestamptz,
   'private','me','love_gesture','any');
 exception when unique_violation then rejected:=true;end;
 if not rejected then raise exception 'Exact duplicate accepted';end if;
 rejected:=false;
 begin
  insert into public.reminders(space_id,title,due_at,visibility,audience,
   reminder_intent,reminder_gesture_kind)
   values(current_setting('qa.space')::uuid,'R36 attempted spoiler',
   now()+interval '2 days',
   'shared','both','love_gesture','thinking');
 exception when check_violation then rejected:=true;end;
 if not rejected then raise exception 'Private intention exposed as shared';end if;
end $r36$;
select set_config('request.jwt.claim.sub',current_setting('qa.b'),true);
do $r36$
begin
 if exists(select 1 from public.reminders
  where title='R36 send love privately')
 then raise exception 'Second partner can read private love prompt';end if;
end $r36$;
select 'PASS: R36 private self-reminders, duplicate guard and no shared spoilers' as result;
rollback;
