-- R24: FCM device registration and durable push outbox.
-- Private notification content never appears in a push payload.
create table if not exists public.push_devices(
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null references auth.users(id) on delete cascade,
 device_id uuid not null,
 fcm_token text not null check(length(fcm_token) between 24 and 4096),
 platform text not null check(platform in ('android','ios')),
 enabled boolean not null default true,
 created_at timestamptz not null default now(),
 last_seen_at timestamptz not null default now(),
 unique(user_id,device_id)
);
create index if not exists push_devices_active_user on public.push_devices(user_id)
 where enabled;
alter table public.push_devices enable row level security;
create policy "Only owner sees own device registration" on public.push_devices
 for select to authenticated using(user_id=(select auth.uid()));
revoke all on public.push_devices from public,anon,authenticated;
grant select(id,user_id,device_id,platform,enabled,last_seen_at)
 on public.push_devices to authenticated;

create or replace function public.register_push_device(
 p_device_id uuid,p_fcm_token text,p_platform text)
returns void language plpgsql security definer set search_path='' as $$
declare who uuid:=auth.uid();
begin
 if who is null or p_device_id is null or
   length(coalesce(p_fcm_token,'')) not between 24 and 4096 or
   p_platform not in ('android','ios') then
  raise exception 'Invalid push-device registration';
 end if;
 -- Prevent a previously signed-out owner from receiving alerts at
 -- this same FCM installation token when another user registers.
 update public.push_devices set enabled=false
 where fcm_token=p_fcm_token and user_id<>who;
 insert into public.push_devices(user_id,device_id,fcm_token,platform,enabled)
 values(who,p_device_id,p_fcm_token,p_platform,true)
 on conflict(user_id,device_id) do update
 set fcm_token=excluded.fcm_token,platform=excluded.platform,
     enabled=true,last_seen_at=now();
end $$;
revoke all on function public.register_push_device(uuid,text,text)
 from public,anon,authenticated;
grant execute on function public.register_push_device(uuid,text,text)
 to authenticated;
create or replace function public.disable_push_device(p_device_id uuid)
returns void language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null then return; end if;
 update public.push_devices set enabled=false,last_seen_at=now()
 where user_id=auth.uid() and device_id=p_device_id;
end $$;
revoke all on function public.disable_push_device(uuid) from public,anon,authenticated;
grant execute on function public.disable_push_device(uuid) to authenticated;

create table if not exists private.push_outbox(
 id uuid primary key default gen_random_uuid(),
 notification_id uuid not null references public.space_notifications(id)
  on delete cascade,
 device_record_id uuid not null references public.push_devices(id)
  on delete cascade,
 event_at timestamptz not null,
 state text not null default 'pending'
  check(state in ('pending','leased','sent','dead')),
 attempts integer not null default 0 check(attempts between 0 and 50),
 next_attempt_at timestamptz not null default now(),
 lease_until timestamptz,
 sent_at timestamptz,
 last_error text,
 created_at timestamptz not null default now(),
 unique(notification_id,device_record_id,event_at)
);
create index if not exists push_outbox_pending
 on private.push_outbox(next_attempt_at,created_at)
 where state in ('pending','leased');
alter table private.push_outbox enable row level security;
revoke all on private.push_outbox from public,anon,authenticated;

create or replace function private.queue_notification_push()
returns trigger language plpgsql security definer set search_path='' as $$
begin
 if tg_op='UPDATE' and not(
    new.created_at is distinct from old.created_at
   or (new.read_at is null and old.read_at is not null)) then
  return new;
 end if;
 insert into private.push_outbox(notification_id,device_record_id,event_at)
 select new.id,d.id,new.created_at
 from public.push_devices d
 where d.user_id=new.recipient_id and d.enabled
 and exists(select 1 from public.space_members m
   where m.space_id=new.space_id and m.user_id=new.recipient_id)
 on conflict(notification_id,device_record_id,event_at) do nothing;
 return new;
end $$;
revoke all on function private.queue_notification_push()
 from public,anon,authenticated;
create trigger push_after_notification_insert
 after insert on public.space_notifications
 for each row execute function private.queue_notification_push();
create trigger push_after_notification_reschedule
 after update of created_at,read_at on public.space_notifications
 for each row execute function private.queue_notification_push();

create or replace function public.claim_push_outbox(p_limit integer default 25)
returns table(delivery_id uuid,registration_token text,notification_id uuid)
language plpgsql security definer set search_path='' as $$
begin
 if current_setting('request.jwt.claim.role',true) is distinct from 'service_role'
 then raise exception 'Backend service authorization required';end if;
 return query
 with candidates as(
   select o.id from private.push_outbox o
   join public.push_devices d on d.id=o.device_record_id
   join public.space_notifications n on n.id=o.notification_id
   where o.state in ('pending','leased')
     and (o.state='pending' or o.lease_until<now())
     and o.next_attempt_at<=now() and o.attempts<8
     and d.enabled and n.recipient_id=d.user_id
     and exists(select 1 from public.space_members m
       where m.space_id=n.space_id and m.user_id=n.recipient_id)
   order by o.next_attempt_at,o.created_at
   limit least(greatest(coalesce(p_limit,25),1),50)
   for update of o skip locked
 ),
 claimed as(
   update private.push_outbox o set state='leased',
      lease_until=now()+interval '3 minutes',attempts=o.attempts+1
   from candidates c where o.id=c.id
   returning o.id,o.device_record_id,o.notification_id
 )
 select c.id,d.fcm_token,c.notification_id from claimed c
 join public.push_devices d on d.id=c.device_record_id;
end $$;
revoke all on function public.claim_push_outbox(integer)
 from public,anon,authenticated;
grant execute on function public.claim_push_outbox(integer) to service_role;

create or replace function public.complete_push_delivery(
 p_delivery uuid,p_result text,p_error text default '')
returns void language plpgsql security definer set search_path='' as $$
begin
 if current_setting('request.jwt.claim.role',true) is distinct from 'service_role'
 then raise exception 'Backend service authorization required';end if;
 if p_result not in ('sent','retry','invalid') then
   raise exception 'Unknown push result';end if;
 if p_result='invalid' then
   update public.push_devices d set enabled=false
   from private.push_outbox o
   where o.id=p_delivery and d.id=o.device_record_id;
 end if;
 update private.push_outbox set
 state=case
   when p_result='sent' then 'sent'
   when p_result='invalid' or attempts>=8 then 'dead'
   else 'pending' end,
 lease_until=null,
 sent_at=case when p_result='sent' then now() else sent_at end,
 next_attempt_at=case when p_result='retry'
   then now()+make_interval(secs=>least(3600,60*power(2,least(attempts,5))::int))
   else next_attempt_at end,
 last_error=left(coalesce(p_error,''),320)
 where id=p_delivery and state='leased';
end $$;
revoke all on function public.complete_push_delivery(uuid,text,text)
 from public,anon,authenticated;
grant execute on function public.complete_push_delivery(uuid,text,text)
 to service_role;
