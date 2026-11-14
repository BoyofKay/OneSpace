-- R22: first-class personal/shared reminders. No prior reminder tables are replaced.
-- Separate recipient state, immutable action history and server-side in-app alerts.
create table public.reminders (
 id uuid primary key default gen_random_uuid(),
 space_id uuid not null references public.spaces(id) on delete cascade,
 created_by uuid not null default auth.uid() references auth.users(id),
 title text not null check (length(btrim(title)) between 1 and 160),
 details text not null default '' check(length(details)<=4000),
 due_at timestamptz not null,
 visibility text not null default 'private' check(visibility in ('private','shared')),
 audience text not null default 'me' check(audience in ('me','partner','both')),
 source_kind text check(source_kind in ('task','calendar','occasion')),
 source_id uuid,
 archived_at timestamptz,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 check(visibility='shared' or audience='me'),
 check((source_kind is null)=(source_id is null))
);
create index reminders_space_due on public.reminders(space_id,due_at)
 where archived_at is null;
alter table public.reminders enable row level security;
create policy "See own or shared reminders" on public.reminders
 for select to authenticated using(
 private.is_space_member(space_id) and
 (visibility='shared' or created_by=(select auth.uid())));
create policy "Create member-owned reminders" on public.reminders
 for insert to authenticated with check(
 created_by=(select auth.uid()) and private.is_space_member(space_id)
 and (visibility='shared' or audience='me'));
create policy "Creators may edit their reminders" on public.reminders
 for update to authenticated using(
 created_by=(select auth.uid()) and private.is_space_member(space_id))
 with check(
 created_by=(select auth.uid()) and private.is_space_member(space_id));
revoke all on public.reminders from public,anon,authenticated;
grant select on public.reminders to authenticated;
grant insert(space_id,title,details,due_at,visibility,audience,source_kind,source_id)
 on public.reminders to authenticated;
grant update(title,details,due_at,archived_at)
 on public.reminders to authenticated;

create table public.reminder_recipients (
 id uuid primary key default gen_random_uuid(),
 reminder_id uuid not null references public.reminders(id) on delete cascade,
 recipient_id uuid not null references auth.users(id),
 state text not null default 'pending'
  check(state in ('pending','follow_up','done')),
 next_alert_at timestamptz,
 last_notified_at timestamptz,
 snoozed_until timestamptz,
 acknowledged_at timestamptz,
 outcome_note text not null default '' check(length(outcome_note)<=1200),
 updated_at timestamptz not null default now(),
 unique(reminder_id,recipient_id)
);
create index reminder_due_recipient on public.reminder_recipients(next_alert_at)
 where state in ('pending','follow_up') and next_alert_at is not null;
create index reminder_recipient_user on public.reminder_recipients(recipient_id,updated_at desc);
alter table public.reminder_recipients enable row level security;
create policy "Own or shared recipient status" on public.reminder_recipients
 for select to authenticated using(exists(
 select 1 from public.reminders r where r.id=reminder_id
 and private.is_space_member(r.space_id)
 and (recipient_id=(select auth.uid()) or r.created_by=(select auth.uid())
 or r.visibility='shared')));
revoke all on public.reminder_recipients from public,anon,authenticated;
grant select on public.reminder_recipients to authenticated;

create table public.reminder_actions (
 id bigint generated always as identity primary key,
 reminder_id uuid not null references public.reminders(id) on delete cascade,
 recipient_id uuid not null references auth.users(id),
 actor_id uuid not null references auth.users(id),
 action text not null check(action in ('done','follow_up','snooze','reopen')),
 note text not null default '' check(length(note)<=1200),
 next_alert_at timestamptz,
 recorded_at timestamptz not null default now()
);
create index reminder_actions_recent on public.reminder_actions(reminder_id,recorded_at desc);
alter table public.reminder_actions enable row level security;
create policy "See authorized reminder history" on public.reminder_actions
 for select to authenticated using(exists(
 select 1 from public.reminders r where r.id=reminder_id
 and private.is_space_member(r.space_id)
 and (recipient_id=(select auth.uid()) or r.created_by=(select auth.uid())
 or r.visibility='shared')));
revoke all on public.reminder_actions from public,anon,authenticated;
grant select on public.reminder_actions to authenticated;

-- Invoked by the INSERT trigger, never from the Flutter API.
create function private.reminder_create_recipients()
returns trigger language plpgsql security definer set search_path='' as $$
declare p uuid;
begin
 if new.audience in ('partner','both') then
  select m.user_id into p from public.space_members m
   where m.space_id=new.space_id and m.user_id<>new.created_by
   order by m.joined_at limit 1;
  if p is null then raise exception 'A partner must be connected'; end if;
  insert into public.reminder_recipients(reminder_id,recipient_id,next_alert_at)
   values(new.id,p,new.due_at);
 end if;
 if new.audience in ('me','both') then
  insert into public.reminder_recipients(reminder_id,recipient_id,next_alert_at)
   values(new.id,new.created_by,new.due_at);
 end if;
 return new;
end $$;
create trigger reminder_initialize_after_insert after insert on public.reminders
 for each row execute function private.reminder_create_recipients();
revoke all on function private.reminder_create_recipients() from public,anon,authenticated;

create function private.reminder_reschedule_on_date_change()
returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.due_at is distinct from old.due_at then
  update public.reminder_recipients rr
   set next_alert_at=new.due_at,last_notified_at=null,
    snoozed_until=null,updated_at=now()
   where rr.reminder_id=new.id and rr.state<>'done';
 end if;
 return new;
end $$;
create trigger reminder_reschedule_after_update after update of due_at on public.reminders
 for each row execute function private.reminder_reschedule_on_date_change();
revoke all on function private.reminder_reschedule_on_date_change() from public,anon,authenticated;

-- A single verified RPC owns all sensitive state changes; the app has no
-- direct permission to update or fabricate recipient outcomes/action history.
create function public.respond_to_reminder(
 p_reminder_id uuid,p_action text,p_note text default '',
 p_snooze_until timestamptz default null)
returns void language plpgsql security definer set search_path='' as $$
declare who uuid:=auth.uid(); rec record; note_text text:=btrim(coalesce(p_note,''));
begin
 if who is null or p_reminder_id is null then raise exception 'Sign in required'; end if;
 if p_action not in ('done','follow_up','snooze','reopen')
    or length(note_text)>1200 then raise exception 'Invalid reminder response'; end if;
 select rr.id,rr.state,r.space_id,r.archived_at into rec
 from public.reminder_recipients rr join public.reminders r on r.id=rr.reminder_id
 where rr.reminder_id=p_reminder_id and rr.recipient_id=who
 for update of rr;
 if not found or rec.archived_at is not null or
   not exists(select 1 from public.space_members m
     where m.space_id=rec.space_id and m.user_id=who) then
   raise exception 'Reminder unavailable';
 end if;
 if p_action='follow_up' and note_text='' then
   raise exception 'Add an outcome note explaining the follow-up';
 end if;
 if p_action='snooze' and (p_snooze_until is null
   or p_snooze_until <= now()+interval '1 minute'
   or p_snooze_until > now()+interval '366 days') then
   raise exception 'Choose a future snooze date and time';
 end if;
 if p_action='done' then
  update public.reminder_recipients set state='done',outcome_note=note_text,
   acknowledged_at=now(),next_alert_at=null,snoozed_until=null,
   updated_at=now() where id=rec.id;
 elsif p_action='follow_up' then
  update public.reminder_recipients set state='follow_up',
   outcome_note=note_text,acknowledged_at=now(),
   next_alert_at=now()+interval '1 day',snoozed_until=null,
   last_notified_at=null,updated_at=now() where id=rec.id;
 elsif p_action='snooze' then
  update public.reminder_recipients set state=case when state='done'
    then 'pending' else state end,
   outcome_note=case when note_text<>'' then note_text else outcome_note end,
   next_alert_at=p_snooze_until,snoozed_until=p_snooze_until,
   last_notified_at=null,updated_at=now() where id=rec.id;
 else
  update public.reminder_recipients set state='pending',acknowledged_at=null,
   next_alert_at=now(),snoozed_until=null,last_notified_at=null,
   updated_at=now() where id=rec.id;
 end if;
 insert into public.reminder_actions(reminder_id,recipient_id,actor_id,
   action,note,next_alert_at)
 select rr.reminder_id,rr.recipient_id,who,p_action,note_text,rr.next_alert_at
 from public.reminder_recipients rr where rr.id=rec.id;
end $$;
revoke all on function public.respond_to_reminder(uuid,text,text,timestamptz)
 from public,anon,authenticated;
grant execute on function public.respond_to_reminder(uuid,text,text,timestamptz)
 to authenticated;

-- Cron runs as the trusted database owner, never as an arbitrary app user.
-- Row locks + due state checks make each in-app alert idempotent.
create function private.dispatch_due_reminders(p_at timestamptz default now())
returns integer language plpgsql security definer set search_path='' as $$
declare item record; dispatched integer:=0;
begin
 for item in
  select rr.id,rr.recipient_id,rr.next_alert_at,r.id reminder_id,
   r.space_id,r.created_by,r.title
  from public.reminder_recipients rr
  join public.reminders r on r.id=rr.reminder_id
  where rr.state in ('pending','follow_up') and rr.next_alert_at<=p_at
   and rr.next_alert_at is not null and r.archived_at is null
   and rr.last_notified_at is distinct from rr.next_alert_at
   and exists(select 1 from public.space_members m
    where m.space_id=r.space_id and m.user_id=rr.recipient_id)
  order by rr.next_alert_at limit 100 for update of rr skip locked
 loop
  insert into public.space_notifications
   (space_id,recipient_id,actor_id,kind,object_kind,object_id,headline,
    generated_automatically)
   values(item.space_id,item.recipient_id,item.created_by,'reminder_due',
    'reminder',item.reminder_id,left('Reminder: '||item.title,200),true);
  update public.reminder_recipients rr set last_notified_at=item.next_alert_at,
    updated_at=p_at where rr.id=item.id;
  dispatched:=dispatched+1;
 end loop;
 return dispatched;
end $$;
revoke all on function private.dispatch_due_reminders(timestamptz)
 from public,anon,authenticated;
select cron.schedule('onespace-due-reminders','*/5 * * * *',
 'select private.dispatch_due_reminders();');
alter publication supabase_realtime add table public.reminders;
alter publication supabase_realtime add table public.reminder_recipients;
