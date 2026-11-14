-- R22 rollback-only live security and reminders workflow test.
begin;
select set_config('qa.space',space_id::text,true)
 from public.space_members group by space_id having count(*)=2 limit 1;
select set_config('qa.a',user_id::text,true)
 from public.space_members where space_id=current_setting('qa.space')::uuid
 order by joined_at,user_id limit 1;
select set_config('qa.b',user_id::text,true)
 from public.space_members where space_id=current_setting('qa.space')::uuid
 order by joined_at desc,user_id desc limit 1;
set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('qa.a'),true);
insert into public.reminders(space_id,title,details,due_at,visibility,audience)
 values
 (current_setting('qa.space')::uuid,'QA-R22-SHARED','Test shared',
   now()+interval '20 minutes','shared','both'),
 (current_setting('qa.space')::uuid,'QA-R22-PRIVATE','Only me',
   now()+interval '20 minutes','private','me');
select set_config('qa.shared',(select id::text from public.reminders
 where title='QA-R22-SHARED'),true);
select set_config('qa.private',(select id::text from public.reminders
 where title='QA-R22-PRIVATE'),true);
do $check$
begin
 if (select count(*) from public.reminder_recipients
   where reminder_id=current_setting('qa.shared')::uuid)<>2
 then raise exception 'Shared reminder needs two recipients'; end if;
 if (select count(*) from public.reminder_recipients
   where reminder_id=current_setting('qa.private')::uuid)<>1
 then raise exception 'Private reminder must have one recipient'; end if;
end $check$;
select set_config('request.jwt.claim.sub',current_setting('qa.b'),true);
do $check$
begin
 if exists(select 1 from public.reminders where title='QA-R22-PRIVATE')
 then raise exception 'Private reminder exposed to partner'; end if;
 if (select count(*) from public.reminders where title='QA-R22-SHARED')<>1
 then raise exception 'Shared reminder not visible'; end if;
end $check$;
select public.respond_to_reminder(current_setting('qa.shared')::uuid,
 'follow_up','Need to confirm details',null);
select public.respond_to_reminder(current_setting('qa.shared')::uuid,
 'done','Done successfully',null);
select set_config('request.jwt.claim.sub',current_setting('qa.a'),true);
select public.respond_to_reminder(current_setting('qa.shared')::uuid,
 'snooze','',now()+interval '2 days');
do $check$
begin
 if (select count(*) from public.reminder_actions where
 reminder_id=current_setting('qa.shared')::uuid)<>3
 then raise exception 'History must capture independent actions'; end if;
 if (select count(*) from public.reminder_recipients where
 reminder_id=current_setting('qa.shared')::uuid and state='done')<>1
 then raise exception 'Partner completion changed wrong user'; end if;
 if (select count(*) from public.reminder_recipients where
 reminder_id=current_setting('qa.shared')::uuid and
 snoozed_until>now()+interval '1 day')<>1
 then raise exception 'Snooze not preserved separately'; end if;
end $check$;
reset role;
select private.dispatch_due_reminders(now()+interval '3 days');
select set_config('request.jwt.claim.sub',current_setting('qa.a'),true);
set local role authenticated;
do $check$
begin
 if (select count(*) from public.space_notifications where kind='reminder_due'
 and object_id=current_setting('qa.shared')::uuid)<>1
 then raise exception 'Due reminder must dispatch once after snooze'; end if;
end $check$;
reset role;
-- Idempotent re-dispatch must not write another alert.
select private.dispatch_due_reminders(now()+interval '3 days');
set local role authenticated;
do $check$
begin
 if (select count(*) from public.space_notifications where kind='reminder_due'
 and object_id=current_setting('qa.shared')::uuid)<>1
 then raise exception 'Due reminder dispatched twice'; end if;
end $check$;
select 'PASS: R22 shared/private RLS, independent outcomes, snooze, cron idempotency' result;
rollback;
