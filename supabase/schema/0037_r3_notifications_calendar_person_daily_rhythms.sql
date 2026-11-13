-- Deployed Supabase migration 20261113082605 (onespace_notifications_calendar_person_and_daily_rhythms).
-- Exact SQL captured from Supabase migration history.
-- OneSpace R3: actionable in-app notifications, calendar ownership, and personal rhythms.
-- Additive only; preserve all existing accounts, events, conversations and saved objects.
create table public.space_notifications (
 id uuid primary key default gen_random_uuid(),
 space_id uuid not null references public.spaces(id) on delete cascade,
 recipient_id uuid not null references auth.users(id) on delete cascade,
 actor_id uuid not null references auth.users(id),
 kind text not null check(kind in ('mention','reply','letter','event')),
 object_kind text not null check(object_kind in ('activity','letter','calendar')),
 object_id uuid not null,
 activity_id uuid references public.activities(id) on delete cascade,
 headline text not null check(char_length(headline) between 1 and 180),
 created_at timestamptz not null default now(),
 read_at timestamptz,
 unique(recipient_id,kind,object_id)
);
create index space_notifications_recipient_recent
 on public.space_notifications(recipient_id,created_at desc);
create index space_notifications_unread
 on public.space_notifications(recipient_id,created_at desc) where read_at is null;
alter table public.space_notifications enable row level security;
create policy "Only the recipient reads their active shared-space notifications"
 on public.space_notifications for select to authenticated
 using(recipient_id=(select auth.uid()) and private.is_space_member(space_id));
create policy "Only the recipient marks their notifications read"
 on public.space_notifications for update to authenticated
 using(recipient_id=(select auth.uid()) and private.is_space_member(space_id))
 with check(recipient_id=(select auth.uid()) and private.is_space_member(space_id));
revoke all on public.space_notifications from public,anon,authenticated;
grant select,update(read_at) on public.space_notifications to authenticated;
alter publication supabase_realtime add table public.space_notifications;

create function private.notify_activity_comment()
returns trigger language plpgsql security definer set search_path='' as $$
declare a record; peer record; previous_author uuid; notification_kind text;
begin
 select space_id,title,visibility into a
 from public.activities where id=new.activity_id;
 if not found or a.visibility <> 'shared' then return new; end if;
 select m.user_id as id, p.display_name as name into peer
 from public.space_members m join public.profiles p on p.id=m.user_id
 where m.space_id=a.space_id and m.user_id<>new.author_id limit 1;
 if not found then return new; end if;
 if position(lower('@'||peer.name) in lower(new.body))>0
    or position(lower('@'||split_part(peer.name,' ',1)) in lower(new.body))>0 then
   notification_kind:='mention';
 elsif new.reply_to is not null then
   select author_id into previous_author from public.activity_comments
     where id=new.reply_to and activity_id=new.activity_id;
   if previous_author=peer.id then notification_kind:='reply'; end if;
 end if;
 if notification_kind is not null then
   insert into public.space_notifications
      (space_id,recipient_id,actor_id,kind,object_kind,object_id,activity_id,headline)
   values(a.space_id,peer.id,new.author_id,notification_kind,'activity',
      new.id,new.activity_id,left(a.title,180))
   on conflict do nothing;
 end if;
 return new;
end; $$;
create trigger activity_comments_notify_partner
 after insert on public.activity_comments for each row
 execute function private.notify_activity_comment();

create function private.notify_sent_letter()
returns trigger language plpgsql security definer set search_path='' as $$
declare peer uuid;
begin
 if new.status <> 'sent' then return new; end if;
 if tg_op='UPDATE' and old.status='sent' then return new; end if;
 select user_id into peer from public.space_members
  where space_id=new.space_id and user_id<>new.author_id limit 1;
 if peer is not null then
  insert into public.space_notifications
   (space_id,recipient_id,actor_id,kind,object_kind,object_id,headline)
  values(new.space_id,peer,new.author_id,'letter','letter',new.id,
         left(new.title,180))
  on conflict do nothing;
 end if;
 return new;
end; $$;
create trigger couple_letters_notify_on_send
 after insert or update on public.couple_letters for each row
 execute function private.notify_sent_letter();

alter table public.space_events
 add column for_user_id uuid references auth.users(id),
 add column starts_at timestamptz,
 add column ends_at timestamptz,
 add column zone_id text check(zone_id is null or char_length(zone_id) between 1 and 100),
 add constraint space_events_timed_range_check
   check ((starts_at is null and ends_at is null)
     or (starts_at is not null and (ends_at is null or ends_at>starts_at)));
grant insert(for_user_id,starts_at,ends_at,zone_id) on public.space_events to authenticated;
grant update(for_user_id,starts_at,ends_at,zone_id) on public.space_events to authenticated;
create function private.validate_event_person()
returns trigger language plpgsql set search_path='' as $$
begin
 if new.for_user_id is not null and not exists(
    select 1 from public.space_members
    where space_id=new.space_id and user_id=new.for_user_id
 ) then raise exception 'The selected person is not part of this space'; end if;
 return new;
end; $$;
create trigger space_event_person_guard
 before insert or update of for_user_id,space_id on public.space_events
 for each row execute function private.validate_event_person();

create function private.notify_new_shared_event()
returns trigger language plpgsql security definer set search_path='' as $$
declare peer uuid;
begin
 if new.visibility<>'shared' then return new; end if;
 select user_id into peer from public.space_members
 where space_id=new.space_id and user_id<>new.created_by limit 1;
 if peer is not null then
  insert into public.space_notifications
   (space_id,recipient_id,actor_id,kind,object_kind,object_id,headline)
  values(new.space_id,peer,new.created_by,'event','calendar',
    new.id,left(new.title,180)) on conflict do nothing;
 end if;
 return new;
end; $$;
create trigger shared_event_notify_partner
 after insert on public.space_events for each row
 execute function private.notify_new_shared_event();

alter table public.profiles
 add column partner_label text check(partner_label is null or
   char_length(btrim(partner_label)) between 1 and 60),
 add column work_start_local time,
 add column work_end_local time,
 add column sleep_start_local time,
 add column sleep_end_local time,
 add column work_days smallint[] not null default array[7,1,2,3,4]::smallint[]
   check(work_days<@array[1,2,3,4,5,6,7]::smallint[]);
grant update(partner_label,work_start_local,work_end_local,
 sleep_start_local,sleep_end_local,work_days)
 on public.profiles to authenticated;
revoke all on function private.notify_activity_comment(),
 private.notify_sent_letter(),private.validate_event_person(),
 private.notify_new_shared_event() from public,anon,authenticated;
