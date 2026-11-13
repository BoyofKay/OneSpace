-- Applied 20261113091420: onespace_consented_scheduled_gestures_cron
-- OneSpace R4: explicitly consented, recipient-local scheduled affection.
create extension if not exists pg_cron with schema pg_catalog;
grant usage on schema cron to postgres;
grant all privileges on all tables in schema cron to postgres;

alter table public.profiles
 add column if not exists receive_automatic_gestures boolean not null default false;
grant update(receive_automatic_gestures) on public.profiles to authenticated;

create table public.gesture_schedules (
 id uuid primary key default gen_random_uuid(),
 space_id uuid not null references public.spaces(id) on delete cascade,
 sender_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
 recipient_id uuid not null references auth.users(id) on delete cascade,
 moment text not null check(moment in ('morning','after_work','goodnight')),
 enabled boolean not null default false,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 check(sender_id<>recipient_id),
 unique(sender_id,recipient_id,moment)
);
create index gesture_schedules_due on public.gesture_schedules(enabled,recipient_id)
 where enabled;
alter table public.gesture_schedules enable row level security;
create policy "Only own schedules visible" on public.gesture_schedules
 for select to authenticated using(
 sender_id=(select auth.uid()) and private.is_space_member(space_id));
create policy "Sender configures schedules for their current partner"
 on public.gesture_schedules for insert to authenticated with check(
 sender_id=(select auth.uid()) and
 private.is_space_member(space_id) and
 exists(select 1 from public.space_members m
  where m.space_id=gesture_schedules.space_id
    and m.user_id=gesture_schedules.recipient_id)
);
create policy "Sender controls only their existing schedules"
 on public.gesture_schedules for update to authenticated
 using(sender_id=(select auth.uid()) and private.is_space_member(space_id))
 with check(sender_id=(select auth.uid()) and private.is_space_member(space_id)
  and exists(select 1 from public.space_members m
   where m.space_id=gesture_schedules.space_id
     and m.user_id=gesture_schedules.recipient_id));
revoke all on public.gesture_schedules from public,anon,authenticated;
grant select on public.gesture_schedules to authenticated;
grant insert(space_id,recipient_id,moment,enabled) on public.gesture_schedules to authenticated;
grant update(enabled) on public.gesture_schedules to authenticated;

alter table public.partner_gestures
 add column if not exists automated boolean not null default false,
 add column if not exists gesture_schedule_id uuid
   references public.gesture_schedules(id) on delete set null,
 add column if not exists recipient_local_day date;
create unique index if not exists partner_gestures_one_automated_per_local_day
 on public.partner_gestures(gesture_schedule_id,recipient_local_day)
 where gesture_schedule_id is not null and recipient_local_day is not null;

-- The application may not impersonate automation: its INSERT grant remains
-- restricted to space_id, recipient_id, kind and message.
create or replace function private.send_due_gestures(
 p_at timestamptz default now()
) returns integer
language plpgsql security definer set search_path='' as $$
declare
 cfg record;
 local_now timestamp;
 target_at timestamp;
 moment_kind text;
 phrases text[];
 item text;
 pos integer;
 sent integer := 0;
 receipt_day date;
 sleeping boolean;
 current_time_local time;
begin
 for cfg in
  select s.id,s.space_id,s.sender_id,s.recipient_id,s.moment,
   p.time_zone,p.sleep_start_local,p.sleep_end_local,
   p.work_end_local,p.work_days
  from public.gesture_schedules s
  join public.profiles p on p.id=s.recipient_id
  where s.enabled=true and p.receive_automatic_gestures=true
   and p.time_zone is not null
   and exists (select 1 from pg_catalog.pg_timezone_names zones
    where zones.name=p.time_zone)
   and exists(select 1 from public.space_members m
    where m.space_id=s.space_id and m.user_id=s.sender_id)
   and exists(select 1 from public.space_members m
    where m.space_id=s.space_id and m.user_id=s.recipient_id)
 loop
  local_now:=p_at at time zone cfg.time_zone;
  receipt_day:=local_now::date;
  current_time_local:=local_now::time;
  target_at:=null;
  moment_kind:=null;
  phrases:=null;
  if cfg.moment='morning' and cfg.sleep_end_local is not null then
    target_at:=receipt_day + cfg.sleep_end_local + interval '15 minutes';
    moment_kind:='morning';
    phrases:=array[
      'Good morning, my love. Wishing you a gentle day.',
      'A warm morning thought for someone very special.',
      'May today bring you a hundred little smiles.',
      'Good morning! Love is cheering you on from afar.',
      'I hope your morning starts with something beautiful.',
      'The day begins with you in my heart.',
      'Sending you sunshine and a little extra courage.',
      'Morning hugs, delivered across the distance.',
      'I hope today brings you peace and happy surprises.',
      'Another day, another reminder that you are loved.'
    ];
  elsif cfg.moment='after_work' and cfg.work_end_local is not null
     and extract(isodow from local_now)::integer=any(cfg.work_days) then
    target_at:=receipt_day + cfg.work_end_local + interval '15 minutes';
    moment_kind:='support';
    phrases:=array[
      'Work is behind you. Sending a well-earned hug.',
      'I hope you can enjoy some rest now.',
      'You did enough today. Be gentle with yourself.',
      'I hope the rest of your evening feels peaceful.',
      'Your effort never goes unnoticed. Proud of you.',
      'May your evening be softer than your workday.',
      'Take a moment for yourself. You deserve it.',
      'Thinking of you as your workday winds down.',
      'Here is a little encouragement for the evening.',
      'Sending care and comfort after a busy day.'
    ];
  elsif cfg.moment='goodnight' and cfg.sleep_start_local is not null then
    target_at:=receipt_day + cfg.sleep_start_local - interval '20 minutes';
    moment_kind:='goodnight';
    phrases:=array[
      'Sweet dreams. You are loved more than words.',
      'Before sleep, a little reminder you are in my heart.',
      'May tonight bring you rest and beautiful dreams.',
      'Goodnight, my love. Rest your busy mind.',
      'Sending peaceful thoughts as bedtime approaches.',
      'A goodnight hug from miles away.',
      'I hope you fall asleep with a smile.',
      'Rest easy. Tomorrow holds another little beginning.',
      'Wishing you a calm and comforting night.',
      'Goodnight. Thinking of you with so much affection.'
    ];
  end if;
  if target_at is null or local_now<target_at
     or local_now>=target_at+interval '10 minutes' then continue; end if;
  -- Never send inside the recipient's configured sleep window.
  sleeping:=false;
  if cfg.sleep_start_local is not null and cfg.sleep_end_local is not null then
    if cfg.sleep_start_local<=cfg.sleep_end_local then
      sleeping:=current_time_local>=cfg.sleep_start_local
        and current_time_local<cfg.sleep_end_local;
    else
      sleeping:=current_time_local>=cfg.sleep_start_local
        or current_time_local<cfg.sleep_end_local;
    end if;
  end if;
  if sleeping then continue; end if;
  pos:=1+mod(
    (pg_catalog.hashtext(cfg.id::text||receipt_day::text)::bigint
      & 2147483647)::integer,
    array_length(phrases,1)
  );
  item:=phrases[pos];
  insert into public.partner_gestures
   (space_id,sender_id,recipient_id,kind,message,automated,
    gesture_schedule_id,recipient_local_day)
   values(cfg.space_id,cfg.sender_id,cfg.recipient_id,
     moment_kind,item,true,cfg.id,receipt_day)
   on conflict do nothing;
  if found then sent:=sent+1; end if;
 end loop;
 return sent;
end;$$;
revoke all on function private.send_due_gestures(timestamptz)
 from public,anon,authenticated;
select cron.schedule(
 'onespace-consented-gestures',
 '*/5 * * * *',
 'select private.send_due_gestures();'
);
