begin;
 select set_config('qa.space',space_id::text,true) from public.space_members
  group by space_id having count(*)=2 limit 1;
 select set_config('qa.a',user_id::text,true) from public.space_members
  where space_id=current_setting('qa.space')::uuid order by joined_at limit 1;
 select set_config('qa.b',user_id::text,true) from public.space_members
  where space_id=current_setting('qa.space')::uuid order by joined_at desc limit 1;
 select set_config('qa.device',gen_random_uuid()::text,true);
 set local role authenticated;
 select set_config('request.jwt.claim.sub',current_setting('qa.a'),true);
 select public.register_push_device(current_setting('qa.device')::uuid,
  repeat('fcm-a-',20),'android');
 do $qa$
 begin
 if (select count(*) from public.push_devices where user_id=auth.uid() and enabled) <1
 then raise exception 'FCM registration not visible to owner';end if;
 end $qa$;
 select set_config('request.jwt.claim.sub',current_setting('qa.b'),true);
 do $qa$
 begin
 if exists(select 1 from public.push_devices
  where device_id=current_setting('qa.device')::uuid) then
  raise exception 'Partner could see private device'; end if;
 end $qa$;
 reset role;
 insert into public.space_notifications(space_id,recipient_id,actor_id,kind,
  object_kind,object_id,headline,generated_automatically)
 values(current_setting('qa.space')::uuid,current_setting('qa.a')::uuid,
 current_setting('qa.b')::uuid,'reminder','reminder',gen_random_uuid(),
 'QA Notification',true);
 select set_config('qa.notification',(
   select id::text from public.space_notifications
   where headline='QA Notification' order by created_at desc limit 1),true);
 do $qa$
 begin
 if (select count(*) from private.push_outbox
  where notification_id=current_setting('qa.notification')::uuid)<>1 then
  raise exception 'One event did not enqueue exactly once';end if;
 end $qa$;
 set local role service_role;
 select set_config('request.jwt.claim.role','service_role',true);
 select set_config('qa.delivery',(
  select delivery_id::text from public.claim_push_outbox(50)
  where notification_id=current_setting('qa.notification')::uuid limit 1),true);
 select public.complete_push_delivery(current_setting('qa.delivery')::uuid,'sent','');
 do $qa$
 begin
 if not exists(select 1 from private.push_outbox
  where id=current_setting('qa.delivery')::uuid and state='sent')
 then raise exception 'FCM delivery acknowledgement not persisted';end if;
 end $qa$;
 select 'PASS: private FCM registration, partner isolation, exactly-one enqueue, service ack' result;
 rollback;