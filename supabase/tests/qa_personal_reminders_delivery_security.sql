-- QA-only, destructive-proof regression: entire transaction rolled back.
-- Covers recipient isolation, personal action history and cron/FCM outbox.
begin;
select set_config('qa.rem_owner',
 (select d.user_id::text from public.push_devices d
   where d.enabled order by d.user_id limit 1),true);
select set_config('qa.rem_other',
 (select ps.owner_id::text from public.user_private_spaces ps
   where ps.owner_id::text<>current_setting('qa.rem_owner')
    order by ps.owner_id limit 1),true);
select set_config('request.jwt.claim.sub',current_setting('qa.rem_owner'),true);
set local role authenticated;
do $create$
declare v_owner uuid:=current_setting('qa.rem_owner')::uuid;
 v_other uuid:=current_setting('qa.rem_other')::uuid; v_id uuid;n integer;
begin
 if v_owner is null or v_other is null then
   raise exception 'Need a device owner and another user';
 end if;
 insert into public.reminders(private_space_id,created_by,title,details,due_at,
    visibility,audience) values(v_owner,v_owner,'Rollback personal reminder',
    'Only the owner may see this',now()+interval '2 minutes','private','me')
 returning id into v_id;
 perform set_config('qa.rem_id',v_id::text,true);
 select count(*) into n from public.reminder_recipients rr
 where rr.reminder_id=v_id and rr.recipient_id=v_owner;
 if n<>1 then raise exception 'Personal reminder has wrong recipient count';end if;
 select count(*) into n from public.record_action_history h
 where h.record_id=v_id and h.record_kind='reminder'
 and h.private_space_id=v_owner;
 if n<>1 then raise exception 'Personal reminder audit missing';end if;
 perform set_config('request.jwt.claim.sub',v_other::text,true);
 select count(*) into n from public.reminders r where r.id=v_id;
 if n<>0 then raise exception 'Other user can see personal reminder';end if;
 select count(*) into n from public.reminder_recipients rr where rr.reminder_id=v_id;
 if n<>0 then raise exception 'Other user can see reminder recipient';end if;
 select count(*) into n from public.record_action_history h where h.record_id=v_id;
 if n<>0 then raise exception 'Other user can see reminder audit';end if;
 perform set_config('request.jwt.claim.sub',v_owner::text,true);
 perform public.respond_to_reminder(v_id,'snooze','',now()+interval '3 minutes');
 select count(*) into n from public.reminder_actions a where a.reminder_id=v_id
   and a.recipient_id=v_owner and a.action='snooze';
 if n<>1 then raise exception 'Owner snooze action missing';end if;
end $create$;
-- A distinct reminder is dispatched by the same backend cron RPC. It queues
-- a personal notification and push outbox only for the recipient's devices.
with ins as (
 insert into public.reminders(private_space_id,created_by,title,details,due_at,
    visibility,audience)
 values(current_setting('qa.rem_owner')::uuid,current_setting('qa.rem_owner')::uuid,
    'Rollback due personal reminder','Private due action',now()+interval '2 minutes',
    'private','me') returning id)
select set_config('qa.due_id',id::text,true) from ins;
reset role;
do $dispatch$
declare n integer;
begin
 perform private.dispatch_due_reminders(now()+interval '3 minutes');
 select count(*) into n from public.space_notifications sn
 where sn.object_id=current_setting('qa.due_id')::uuid
  and sn.private_space_id=current_setting('qa.rem_owner')::uuid
  and sn.space_id is null;
 if n<>1 then raise exception 'Due personal notification missing: %',n;end if;
 select count(*) into n from private.push_outbox o
 join public.space_notifications sn on sn.id=o.notification_id
 where sn.object_id=current_setting('qa.due_id')::uuid;
 if n<1 then raise exception 'Personal reminder push was not queued';end if;
end $dispatch$;
select set_config('request.jwt.claim.sub',current_setting('qa.rem_other'),true);
set local role authenticated;
do $foreign$
declare n integer;
begin
 select count(*) into n from public.space_notifications sn
 where sn.object_id=current_setting('qa.due_id')::uuid;
 if n<>0 then raise exception 'Other user can read private reminder notification';end if;
end $foreign$;
select set_config('request.jwt.claim.sub',current_setting('qa.rem_owner'),true);
do $own$
declare n integer;
begin
 select count(*) into n from public.space_notifications sn
 where sn.object_id=current_setting('qa.due_id')::uuid;
 if n<>1 then raise exception 'Owner cannot read own due notification';end if;
end $own$;
rollback;
