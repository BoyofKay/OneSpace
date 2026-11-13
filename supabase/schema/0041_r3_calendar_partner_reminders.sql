-- Deployed Supabase migration 20261113090237 (shared_calendar_partner_remind_me_now).
-- Exact SQL captured from Supabase migration history.
-- Manual partner reminders. Explicitly sent, one per shared event per sender/day.
create table public.calendar_partner_reminders (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.space_events(id) on delete cascade,
  space_id uuid not null references public.spaces(id) on delete cascade,
  sender_id uuid not null default auth.uid() references auth.users(id),
  recipient_id uuid not null references auth.users(id),
  sent_day date not null default current_date,
  created_at timestamptz not null default now(),
  constraint calendar_partner_reminders_distinct_users check(sender_id<>recipient_id),
  unique(event_id,sender_id,recipient_id,sent_day)
);
create index calendar_partner_reminders_recent on public.calendar_partner_reminders
  (space_id,created_at desc);
alter table public.calendar_partner_reminders enable row level security;
create policy "Only involved partners see event reminders"
 on public.calendar_partner_reminders for select to authenticated
 using (private.is_space_member(space_id) and
   ((select auth.uid())=sender_id or (select auth.uid())=recipient_id));
create policy "Only partner may remind the other about a shared event"
 on public.calendar_partner_reminders for insert to authenticated
 with check(
   sender_id=(select auth.uid()) and
   private.is_space_member(space_id) and
   recipient_id<>(select auth.uid()) and
   exists(select 1 from public.space_members m
     where m.space_id=calendar_partner_reminders.space_id and
       m.user_id=calendar_partner_reminders.recipient_id) and
   exists(select 1 from public.space_events e
     where e.id=calendar_partner_reminders.event_id and
       e.space_id=calendar_partner_reminders.space_id and
       e.visibility='shared' and e.archived_at is null)
 );
revoke all on public.calendar_partner_reminders from public,anon,authenticated;
grant select on public.calendar_partner_reminders to authenticated;
grant insert(event_id,space_id,recipient_id) on public.calendar_partner_reminders
  to authenticated;

alter table public.space_notifications
  drop constraint if exists space_notifications_kind_check;
alter table public.space_notifications
  add constraint space_notifications_kind_check
  check(kind in ('mention','reply','letter','event','gesture','reminder'));
alter table public.space_notifications
  add column if not exists calendar_event_id uuid
    references public.space_events(id) on delete cascade;
create function private.notify_calendar_partner_reminder()
returns trigger language plpgsql security definer set search_path='' as $$
declare v_title text;
begin
  select title into v_title from public.space_events
    where id=new.event_id and space_id=new.space_id and visibility='shared'
      and archived_at is null;
  if not found then raise exception 'Shared event unavailable'; end if;
  insert into public.space_notifications
    (space_id,recipient_id,actor_id,kind,object_kind,object_id,
      calendar_event_id,headline)
  values(new.space_id,new.recipient_id,new.sender_id,
    'reminder','calendar',new.id,new.event_id,left(v_title,180));
  return new;
end;$$;
revoke all on function private.notify_calendar_partner_reminder()
  from public,anon,authenticated;
create trigger calendar_partner_reminders_deliver
 after insert on public.calendar_partner_reminders for each row
 execute function private.notify_calendar_partner_reminder();
