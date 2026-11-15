-- R47: Reminders for real life (decisions D5, D10, D14; spec B-01..B-03, B-11).
-- * Repeating reminders (daily / weekly on chosen days / monthly / yearly,
--   every N, several times a day, optional end date), computed in a fixed
--   IANA time zone so daylight-saving changes never shift the alarm.
-- * Quiet hours: alerts a partner creates for you wait until your wake-up
--   time, unless the partner marked the reminder Urgent. Your own reminders
--   always fire on time.
-- * Linked item closed (checklist completed/cancelled, event or occasion
--   removed/finished) stops the reminder instead of alerting.
-- * A repeating occurrence left unanswered when the next one fires is
--   recorded as Missed (system action).
-- * First-class reminders appear in Today: Needs attention and Coming up.
-- Additive and non-destructive: existing one-time reminders behave as before.

-- 1. Columns -------------------------------------------------------------
alter table public.reminders
  add column if not exists repeat_rule jsonb,
  add column if not exists urgent boolean not null default false,
  add column if not exists source_closed_at timestamptz;
alter table public.reminders
  add constraint reminders_repeat_rule_shape check (
    repeat_rule is null or (jsonb_typeof(repeat_rule)='object'
      and length(repeat_rule::text)<=1200));

alter table public.reminder_recipients
  add column if not exists open_occurrence_at timestamptz;

alter table public.reminder_actions
  drop constraint if exists reminder_actions_action_check;
alter table public.reminder_actions
  add constraint reminder_actions_action_check check (action in
   ('done','follow_up','snooze','reopen','missed','source_closed','deferred'));
-- System actions (missed, source closed, deferred) have no human actor.
alter table public.reminder_actions alter column actor_id drop not null;

grant insert(repeat_rule,urgent) on public.reminders to authenticated;
grant update(repeat_rule,urgent) on public.reminders to authenticated;

-- 2. Repeat rule validation and occurrence maths ---------------------------
-- Rule shape:
-- {"freq":"daily|weekly|monthly|yearly","interval":1..99,
--  "weekdays":[1..7] (ISO, weekly only), "times":["HH:MM",...] (1..6),
--  "tz":"Area/City", "until":"YYYY-MM-DD" | null}
create or replace function private.reminder_rule_valid(p_rule jsonb)
returns boolean language plpgsql immutable set search_path='' as $$
declare t text; d text;
begin
 if p_rule is null then return true; end if;
 if coalesce(p_rule->>'freq','') not in ('daily','weekly','monthly','yearly')
  then return false; end if;
 if coalesce((p_rule->>'interval')::int,1) not between 1 and 99 then return false; end if;
 if jsonb_typeof(p_rule->'times') is distinct from 'array'
  or jsonb_array_length(p_rule->'times') not between 1 and 6 then return false; end if;
 for t in select jsonb_array_elements_text(p_rule->'times') loop
  if t !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' then return false; end if;
 end loop;
 if p_rule->>'freq'='weekly' then
  if jsonb_typeof(p_rule->'weekdays') is distinct from 'array'
   or jsonb_array_length(p_rule->'weekdays') not between 1 and 7 then return false; end if;
  for d in select jsonb_array_elements_text(p_rule->'weekdays') loop
   if d !~ '^[1-7]$' then return false; end if;
  end loop;
 end if;
 if coalesce(p_rule->>'tz','')='' then return false; end if;
 if p_rule ? 'until' and p_rule->>'until' is not null
  and not pg_catalog.pg_input_is_valid(p_rule->>'until','date') then return false; end if;
 return true;
exception when others then return false;
end $$;

-- Next occurrence strictly after p_after for a rule anchored at p_anchor
-- (the reminder's first occurrence). Returns null when the rule has ended.
create or replace function private.reminder_next_occurrence(
  p_rule jsonb, p_anchor timestamptz, p_after timestamptz)
returns timestamptz language plpgsql stable set search_path='' as $$
declare
 tz text:=p_rule->>'tz';
 freq text:=p_rule->>'freq';
 step int:=greatest(coalesce((p_rule->>'interval')::int,1),1);
 until_day date:=case when p_rule->>'until' is null then null
   else (p_rule->>'until')::date end;
 anchor_day date;
 day date;
 last_day date;
 t text;
 candidate timestamptz;
 best timestamptz;
 ok boolean;
 month_diff int;
 anchor_dom int;
begin
 if p_rule is null or not exists(select 1 from pg_catalog.pg_timezone_names z
   where z.name=tz) then return null; end if;
 anchor_day:=(p_anchor at time zone tz)::date;
 anchor_dom:=extract(day from anchor_day)::int;
 day:=greatest((p_after at time zone tz)::date, anchor_day);
 last_day:=day+least(400*step,3700);
 while day<=last_day loop
  if until_day is not null and day>until_day then return null; end if;
  if freq='daily' then
   ok:=mod(day-anchor_day,step)=0;
  elsif freq='weekly' then
   ok:=(p_rule->'weekdays') @> to_jsonb(extract(isodow from day)::int)
     and mod(((date_trunc('week',day)::date-date_trunc('week',anchor_day)::date)/7),step)=0;
  elsif freq='monthly' then
   month_diff:=(extract(year from day)::int-extract(year from anchor_day)::int)*12
     +extract(month from day)::int-extract(month from anchor_day)::int;
   -- Day 31 falls back to the month's last day (e.g. 30 Apr, 28/29 Feb).
   ok:=mod(month_diff,step)=0 and extract(day from day)::int=least(anchor_dom,
     extract(day from (date_trunc('month',day)+interval '1 month - 1 day'))::int);
  elsif freq='yearly' then
   ok:=mod(extract(year from day)::int-extract(year from anchor_day)::int,step)=0
     and extract(month from day)=extract(month from anchor_day)
     and extract(day from day)::int=least(anchor_dom,
       extract(day from (date_trunc('month',day)+interval '1 month - 1 day'))::int);
  else
   return null;
  end if;
  if ok then
   best:=null;
   for t in select jsonb_array_elements_text(p_rule->'times') loop
    candidate:=(day+t::time) at time zone tz;
    if candidate>p_after and candidate>=p_anchor and (best is null or candidate<best) then
     best:=candidate;
    end if;
   end loop;
   if best is not null then return best; end if;
  end if;
  day:=day+1;
 end loop;
 return null;
end $$;

-- Wake-up moment when p_at falls inside the user's sleep window (respecting
-- days-off overrides), otherwise null. No sleep window set = never quiet.
create or replace function private.reminder_quiet_until(p_user uuid, p_at timestamptz)
returns timestamptz language plpgsql stable set search_path='' as $$
declare
 p record; local_now timestamp; today date; sleep_t time; wake_t time;
 wake_day date;
begin
 select time_zone,sleep_start_local,sleep_end_local into p
  from public.profiles where id=p_user;
 if p.time_zone is null or p.sleep_start_local is null or p.sleep_end_local is null
  or not exists(select 1 from pg_catalog.pg_timezone_names z where z.name=p.time_zone)
  then return null; end if;
 local_now:=p_at at time zone p.time_zone;
 today:=local_now::date;
 -- Bedtime tonight can be moved by tomorrow's day off; wake-up by today's.
 sleep_t:=coalesce((select d.night_before_sleep_at from public.personal_days_off d
   where d.user_id=p_user and d.off_date=today+1),p.sleep_start_local);
 wake_t:=coalesce((select d.off_day_wake_at from public.personal_days_off d
   where d.user_id=p_user and d.off_date=today),p.sleep_end_local);
 if sleep_t=wake_t then return null; end if;
 if sleep_t>wake_t then
  -- Overnight window, e.g. 23:00 → 07:00.
  if local_now::time>=sleep_t then
   wake_day:=today+1;
   wake_t:=coalesce((select d.off_day_wake_at from public.personal_days_off d
     where d.user_id=p_user and d.off_date=wake_day),p.sleep_end_local);
  elsif local_now::time<wake_t then
   wake_day:=today;
  else
   return null;
  end if;
 else
  -- Same-day window, e.g. 01:00 → 09:00 (night-shift sleepers).
  if local_now::time>=sleep_t and local_now::time<wake_t then wake_day:=today;
  else return null; end if;
 end if;
 return (wake_day+wake_t) at time zone p.time_zone;
end $$;

-- Is the reminder's linked item finished, cancelled or removed?
create or replace function private.reminder_source_closed(p_kind text, p_id uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select case p_kind
  when 'task' then not exists(select 1 from public.tasks t
     where t.id=p_id and t.status='open')
  when 'calendar' then not exists(select 1 from public.space_events e
     where e.id=p_id and e.archived_at is null)
  when 'occasion' then not exists(select 1 from public.occasion_plans o
     where o.id=p_id and o.archived_at is null
       and o.status not in ('celebrated','cancelled'))
  else false end;
$$;

-- 3. Normalise schedule on create/edit ------------------------------------
create or replace function private.reminder_normalize_schedule()
returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.repeat_rule is not null then
  if not private.reminder_rule_valid(new.repeat_rule) then
   raise exception 'Repeat settings are incomplete or invalid';
  end if;
  if tg_op='INSERT' or new.repeat_rule is distinct from old.repeat_rule
     or new.due_at is distinct from old.due_at then
   -- due_at becomes the first real occurrence at or after the chosen start.
   -- Minute precision: a start of 10:23:40 must still match a 10:23 time.
   new.due_at:=date_trunc('minute',new.due_at);
   new.due_at:=coalesce(private.reminder_next_occurrence(
     new.repeat_rule,new.due_at,new.due_at-interval '1 second'),new.due_at);
  end if;
 end if;
 if new.audience='me' then new.urgent:=false; end if;
 return new;
end $$;
drop trigger if exists reminder_normalize_schedule on public.reminders;
create trigger reminder_normalize_schedule before insert or update of due_at,repeat_rule,urgent,audience
 on public.reminders for each row execute function private.reminder_normalize_schedule();

create or replace function private.reminder_reschedule_on_date_change()
returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.due_at is distinct from old.due_at
    or new.repeat_rule is distinct from old.repeat_rule then
  update public.reminder_recipients rr
   set next_alert_at=new.due_at,last_notified_at=null,open_occurrence_at=null,
    snoozed_until=null,updated_at=now(),
    state=case when new.repeat_rule is not null then 'pending' else rr.state end
   where rr.reminder_id=new.id
     and (rr.state<>'done' or new.repeat_rule is not null);
 end if;
 return new;
end $$;
drop trigger if exists reminder_reschedule_after_update on public.reminders;
create trigger reminder_reschedule_after_update after update of due_at,repeat_rule
 on public.reminders for each row execute function private.reminder_reschedule_on_date_change();

-- 4. Delivery --------------------------------------------------------------
create or replace function private.dispatch_due_reminders(p_at timestamptz default now())
returns integer language plpgsql security definer set search_path='' as $$
declare item record; dispatched integer:=0; quiet timestamptz; nxt timestamptz;
begin
 for item in
  select rr.id,rr.recipient_id,rr.next_alert_at,rr.open_occurrence_at,
   r.id reminder_id,r.space_id,r.created_by,r.title,r.urgent,r.repeat_rule,
   r.due_at,r.source_kind,r.source_id,r.source_closed_at
  from public.reminder_recipients rr
  join public.reminders r on r.id=rr.reminder_id
  where rr.state in ('pending','follow_up') and rr.next_alert_at<=p_at
   and rr.next_alert_at is not null and r.archived_at is null
   and rr.last_notified_at is distinct from rr.next_alert_at
   and exists(select 1 from public.space_members m
    where m.space_id=r.space_id and m.user_id=rr.recipient_id)
  order by rr.next_alert_at limit 100 for update of rr skip locked
 loop
  -- a) Linked item finished, cancelled or removed: stop, never alert.
  if item.source_kind is not null
     and private.reminder_source_closed(item.source_kind,item.source_id) then
   update public.reminders set source_closed_at=coalesce(source_closed_at,p_at)
    where id=item.reminder_id;
   update public.reminder_recipients set next_alert_at=null,open_occurrence_at=null,
    updated_at=p_at where id=item.id;
   insert into public.reminder_actions(reminder_id,recipient_id,actor_id,action,note)
    values(item.reminder_id,item.recipient_id,null,'source_closed',
     'The linked item was completed, cancelled or removed.');
   continue;
  end if;
  -- b) Quiet hours for partner-created, non-urgent alerts.
  if item.recipient_id<>item.created_by and not item.urgent then
   quiet:=private.reminder_quiet_until(item.recipient_id,p_at);
   if quiet is not null and quiet>item.next_alert_at then
    update public.reminder_recipients set next_alert_at=quiet,updated_at=p_at
     where id=item.id;
    insert into public.reminder_actions(reminder_id,recipient_id,actor_id,action,note,next_alert_at)
     values(item.reminder_id,item.recipient_id,null,'deferred',
      'Held during sleep hours; delivered at wake-up.',quiet);
    continue;
   end if;
  end if;
  -- c) A repeating occurrence still unanswered becomes Missed.
  if item.repeat_rule is not null and item.open_occurrence_at is not null then
   insert into public.reminder_actions(reminder_id,recipient_id,actor_id,action,note,next_alert_at)
    values(item.reminder_id,item.recipient_id,null,'missed','',item.open_occurrence_at);
  end if;
  -- d) Alert (one notification row per reminder and person; re-timed each time).
  insert into public.space_notifications
   (space_id,recipient_id,actor_id,kind,object_kind,object_id,headline,
    generated_automatically)
   values(item.space_id,item.recipient_id,item.created_by,'reminder',
    'reminder',item.reminder_id,
    left(case when item.urgent then 'Urgent: ' else 'Reminder: ' end||item.title,180),true)
   on conflict(recipient_id,kind,object_id)
   do update set headline=excluded.headline,read_at=null,
     created_at=p_at,generated_automatically=true;
  -- e) Schedule the next occurrence for repeating reminders.
  if item.repeat_rule is not null then
   nxt:=private.reminder_next_occurrence(item.repeat_rule,item.due_at,
     greatest(item.next_alert_at,p_at));
   update public.reminder_recipients rr set
     state='pending',open_occurrence_at=item.next_alert_at,
     last_notified_at=item.next_alert_at,next_alert_at=nxt,
     snoozed_until=null,updated_at=p_at
    where rr.id=item.id;
  else
   update public.reminder_recipients rr set last_notified_at=item.next_alert_at,
     updated_at=p_at where rr.id=item.id;
  end if;
  dispatched:=dispatched+1;
 end loop;
 return dispatched;
end $$;

-- 5. Responding -------------------------------------------------------------
create or replace function public.respond_to_reminder(p_reminder_id uuid, p_action text,
  p_note text default '', p_snooze_until timestamptz default null)
returns void language plpgsql security definer set search_path='' as $$
declare who uuid:=auth.uid(); rec record; note_text text:=btrim(coalesce(p_note,''));
begin
 if who is null or p_reminder_id is null then raise exception 'Sign in required'; end if;
 if p_action not in ('done','follow_up','snooze','reopen')
    or length(note_text)>1200 then raise exception 'Invalid reminder response'; end if;
 select rr.id,rr.state,rr.next_alert_at,rr.open_occurrence_at,
   r.space_id,r.archived_at,r.repeat_rule,r.due_at into rec
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

 if rec.repeat_rule is not null then
  -- Repeating: actions apply to the current occurrence; the schedule continues.
  if p_action='done' then
   if rec.open_occurrence_at is null then
    -- Done early for the upcoming occurrence (allowed within 12 hours).
    if rec.next_alert_at is null or rec.next_alert_at>now()+interval '12 hours' then
     raise exception 'Nothing is due yet for this repeating reminder';
    end if;
    update public.reminder_recipients set state='pending',outcome_note=note_text,
     acknowledged_at=now(),
     next_alert_at=private.reminder_next_occurrence(rec.repeat_rule,rec.due_at,rec.next_alert_at),
     last_notified_at=null,snoozed_until=null,updated_at=now() where id=rec.id;
   else
    update public.reminder_recipients set state='pending',outcome_note=note_text,
     acknowledged_at=now(),open_occurrence_at=null,snoozed_until=null,
     updated_at=now() where id=rec.id;
   end if;
  elsif p_action='follow_up' then
   update public.reminder_recipients set outcome_note=note_text,acknowledged_at=now(),
    open_occurrence_at=null,updated_at=now() where id=rec.id;
  elsif p_action='snooze' then
   update public.reminder_recipients set open_occurrence_at=null,
    outcome_note=case when note_text<>'' then note_text else outcome_note end,
    next_alert_at=p_snooze_until,snoozed_until=p_snooze_until,
    last_notified_at=null,updated_at=now() where id=rec.id;
  else
   update public.reminder_recipients set state='pending',acknowledged_at=null,
    next_alert_at=now(),snoozed_until=null,last_notified_at=null,
    updated_at=now() where id=rec.id;
  end if;
 elsif p_action='done' then
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
revoke all on function public.respond_to_reminder(uuid,text,text,timestamptz) from public,anon;
grant execute on function public.respond_to_reminder(uuid,text,text,timestamptz) to authenticated;

-- 6. Today: Needs attention (reminders added; dead to-do "urgent" branch removed)
create or replace function public.onespace_my_attention(p_today date)
returns jsonb language sql stable set search_path='' as $$
 with me as (select auth.uid() as id),
 my_space as (
   select space_id from public.space_members m,me
   where m.user_id=me.id
 ),
 my_zone as (
   select coalesce((select p.time_zone from public.profiles p,me where p.id=me.id
     and exists(select 1 from pg_catalog.pg_timezone_names z where z.name=p.time_zone)),
     'UTC') as tz
 ),
 candidates as (
   select 'activity'::text as source,a.id as object_id,a.id as activity_id,
     a.title,'activity'::text as kind,a.due_on,a.priority,
     case when a.due_on<p_today then 'Overdue activity'
       when a.due_on=p_today then 'Activity due today'
       when a.due_on=p_today+1 then 'Activity due tomorrow'
       when a.priority='urgent' then 'Urgent activity'
       else 'High-priority activity approaching' end as reason,
     case when a.due_on<p_today then 0
       when a.due_on=p_today then 1
       when a.due_on=p_today+1 then 3
       when a.priority='urgent' then 4 else 5 end as score
   from public.activities a join my_space m on m.space_id=a.space_id
   where a.archived_at is null and a.stage not in ('completed','cancelled')
     and (a.due_on<=p_today+1
       or (a.priority='high' and a.due_on between p_today+2 and p_today+3)
       or (a.priority='urgent' and a.due_on is null))
     and not exists (select 1 from public.activity_attention_snoozes s
       where s.activity_id=a.id and s.component_id is null
         and s.user_id=(select id from me) and s.snoozed_until>=p_today)
   union all
   select 'activity',a.id,a.id,
     coalesce(nullif(c.label,''),a.title),'reminder',
     v.due_on,a.priority,
     case when v.due_on<p_today then 'Overdue reminder'
       when v.due_on=p_today then 'Reminder due today'
       else 'Reminder due tomorrow' end,
     case when v.due_on<p_today then 0 when v.due_on=p_today then 1 else 3 end
   from public.activity_components c
   join public.activities a on a.id=c.activity_id
   join my_space m on m.space_id=a.space_id
   cross join lateral (select case
     when pg_catalog.pg_input_is_valid(c.payload->>'value','date')
       then (c.payload->>'value')::date end as due_on) v
   where a.archived_at is null and c.archived_at is null
     and a.stage not in ('completed','cancelled') and c.kind='reminder'
     and coalesce(c.payload->>'status','open')<>'done'
     and v.due_on<=p_today+1
     and not exists(select 1 from public.activity_attention_snoozes s
       where s.activity_id=a.id and s.user_id=(select id from me)
         and s.snoozed_until>=p_today
         and (s.component_id is null or s.component_id=c.id))
   union all
   -- R47: first-class reminders addressed to me.
   select 'reminder',r.id,null::uuid,r.title,'reminder',x.due_on,
     case when r.urgent then 'urgent' else 'normal' end,
     case when rr.state='follow_up' then 'Reminder needs follow-up'
       when x.due_on<p_today then 'Overdue reminder'
       when rr.open_occurrence_at is not null then 'Reminder due now'
       else 'Reminder due today' end,
     case when x.due_on<p_today then 0 when rr.open_occurrence_at is not null then 1
       when rr.state='follow_up' then 2 else 1 end
   from public.reminder_recipients rr
   join public.reminders r on r.id=rr.reminder_id
   join my_space m on m.space_id=r.space_id
   cross join my_zone z
   cross join lateral (select (coalesce(rr.open_occurrence_at,rr.next_alert_at)
     at time zone z.tz)::date as due_on) x
   where rr.recipient_id=(select id from me) and r.archived_at is null
     and r.source_closed_at is null
     and (rr.snoozed_until is null or rr.snoozed_until<=now())
     and (rr.open_occurrence_at is not null
       or (rr.state in ('pending','follow_up') and rr.next_alert_at is not null
           and x.due_on<=p_today
           and (r.repeat_rule is null or rr.next_alert_at<=now())))
   union all
   select 'task',t.id,null::uuid,t.title,'task',t.target_date,t.priority,
     case when t.target_date<p_today then 'Overdue to-do'
       when t.target_date=p_today then 'To-do due today'
       when t.target_date=p_today+1 then 'To-do due tomorrow'
       else 'High-priority to-do approaching' end,
     case when t.target_date<p_today then 0
       when t.target_date=p_today then 1
       when t.target_date=p_today+1 then 3 else 5 end
   from public.tasks t join my_space m on m.space_id=t.space_id,me
   where t.status='open'
     and (t.assigned_to=me.id or
       (t.assigned_to is null and (t.created_by=me.id or t.visibility='shared')))
     and (t.target_date<=p_today+1
       or (t.priority='high' and t.target_date between p_today+2 and p_today+3))
   union all
   select 'checkin',r.id,null::uuid,
     'Your partner asked how you are feeling','checkin',
     null::date,'normal','Respond to a partner check-in',2
   from public.partner_checkin_requests r
   join my_space m on m.space_id=r.space_id,me
   where r.recipient_id=me.id and r.responded_at is null
     and (r.expires_at is null or r.expires_at > now())
   union all
   select 'activity',a.id,a.id,a.title,'mention',
     null::date,'normal',
     case when n.kind='mention' then 'Your partner mentioned you'
       else 'Unread Activity reply' end,2
   from public.space_notifications n
   join public.activities a on a.id=n.activity_id
   join my_space m on m.space_id=n.space_id,me
   where n.recipient_id=me.id and n.read_at is null
     and n.kind in ('mention','reply') and n.object_kind='activity'
     and a.archived_at is null
 ),
 filtered as (
   select c.* from candidates c
   left join public.user_attention_snoozes us
     on us.user_id=(select id from me)
       and us.source=c.source and us.object_id=c.object_id
       and us.snoozed_until>=p_today
   where us.object_id is null
 ),
 grouped as (
   select distinct on(source,object_id)
     source,object_id,activity_id,title,kind,due_on,priority,reason,score
   from filtered
   order by source,object_id,score,due_on nulls last,title
 ),
 nearest as(
   select * from grouped order by score,due_on nulls last,title limit 20
 )
 select coalesce(jsonb_agg(jsonb_build_object(
   'id',object_id,'source',source,'activity_id',activity_id,
   'title',title,'kind',kind,'due_on',due_on,
   'priority',priority,'reason',reason,'score',score)
   order by score,due_on nulls last,title),'[]'::jsonb)
 from nearest;
$$;

-- 7. Today: Coming up (next 7 days) now lists reminders addressed to me.
create or replace function public.onespace_coming_up(p_today date)
returns jsonb language sql stable set search_path='' as $$
 with my_spaces as (
   select space_id from public.space_members
   where user_id=(select auth.uid())
 ), my_zone as (
   select coalesce((select p.time_zone from public.profiles p where p.id=(select auth.uid())
     and exists(select 1 from pg_catalog.pg_timezone_names z where z.name=p.time_zone)),
     'UTC') as tz
 ), entries as (
   select 'calendar'::text as source,e.id::text as source_id,
      e.title,e.kind,
      case when e.recurrence='yearly'
        then public.onespace_annual_date(e.event_date,p_today)
        else e.event_date end as day,
      null::uuid as activity_id,null::uuid as trip_id,null::uuid as occasion_id
   from public.space_events e
   join my_spaces sm on sm.space_id=e.space_id
   where e.archived_at is null
   union all
   select 'reminder',r.id::text,r.title,
     case when r.repeat_rule is null then 'reminder' else 'repeating_reminder' end,
     (rr.next_alert_at at time zone z.tz)::date,null::uuid,null::uuid,null::uuid
   from public.reminder_recipients rr
   join public.reminders r on r.id=rr.reminder_id
   join my_spaces sm on sm.space_id=r.space_id
   cross join my_zone z
   where rr.recipient_id=(select auth.uid()) and r.archived_at is null
     and r.source_closed_at is null and rr.state in ('pending','follow_up')
     and rr.next_alert_at is not null
   union all
   select 'todo',t.id::text,t.title,'todo',t.target_date,null::uuid,null::uuid,null::uuid
   from public.tasks t
   join my_spaces sm on sm.space_id=t.space_id
   where t.status='open' and t.target_date is not null
   union all
   select 'experience',e.id::text,e.title,e.category,e.planned_on,null::uuid,null::uuid,null::uuid
   from public.shared_experiences e
   join my_spaces sm on sm.space_id=e.space_id
   where e.archived_at is null and e.status<>'enjoyed' and e.planned_on is not null
   union all
   select 'trip',t.id::text,t.title,'trip',t.start_on,null::uuid,t.id,null::uuid
   from public.shared_trips t
   join my_spaces sm on sm.space_id=t.space_id
   where t.archived_at is null and t.start_on is not null
    and t.status not in ('completed','cancelled')
   union all
   select 'trip_item',i.id::text,i.title,i.kind,i.local_date,null::uuid,t.id,null::uuid
   from public.trip_items i
   join public.shared_trips t on t.id=i.trip_id
   join my_spaces sm on sm.space_id=t.space_id
   where i.archived_at is null and i.done=false and i.local_date is not null
     and t.archived_at is null and t.status not in ('completed','cancelled')
   union all
   select 'occasion',p.id::text,'Occasion: '||p.title,p.kind,
    case when p.annual then public.onespace_annual_date(p.occasion_on,p_today)
     else p.occasion_on end,null::uuid,null::uuid,p.id
   from public.occasion_plans p
   join my_spaces sm on sm.space_id=p.space_id
   where p.archived_at is null and p.status not in ('celebrated','cancelled')
   union all
   select 'occasion_prep',p.id::text,'Prepare: '||p.title,'occasion_prep',
    (case when p.annual then public.onespace_annual_date(p.occasion_on,p_today)
      else p.occasion_on end)-p.prep_lead_days,null::uuid,null::uuid,p.id
   from public.occasion_plans p
   join my_spaces sm on sm.space_id=p.space_id
   where p.archived_at is null and p.status in ('planning','preparing')
   union all
   select 'occasion_savings',p.id::text,'Save for: '||p.title,'occasion_savings',
    (case when p.annual then public.onespace_annual_date(p.occasion_on,p_today)
      else p.occasion_on end)-p.saving_lead_days,null::uuid,null::uuid,p.id
   from public.occasion_plans p
   join my_spaces sm on sm.space_id=p.space_id
   where p.archived_at is null and p.status in ('planning','preparing')
    and p.budget is not null and p.budget>0
   union all
   select 'occasion_step',s.id::text,s.title,'occasion_step',s.due_on,
    null::uuid,null::uuid,p.id
   from public.occasion_plan_steps s
   join public.occasion_plans p on p.id=s.plan_id
   join my_spaces sm on sm.space_id=p.space_id
   where s.archived_at is null and s.done=false and s.due_on is not null
    and p.archived_at is null and p.status not in ('celebrated','cancelled')
   union all
   select 'activity',a.id::text,a.title,'activity',a.due_on,a.id,null::uuid,null::uuid
   from public.activities a
   join my_spaces sm on sm.space_id=a.space_id
   where a.archived_at is null
     and a.stage not in ('cancelled','completed')
     and a.due_on is not null
   union all
   select 'component',c.id::text,
     coalesce(nullif(c.label,''),a.title),c.kind,
     case when pg_catalog.pg_input_is_valid(c.payload->>'value','date')
       then (c.payload->>'value')::date end, a.id,null::uuid,null::uuid
   from public.activity_components c
   join public.activities a on a.id=c.activity_id
   join my_spaces sm on sm.space_id=a.space_id
   where a.archived_at is null and c.archived_at is null
    and a.stage not in ('cancelled','completed')
    and c.kind in ('date','reminder','countdown')
    and (c.kind<>'reminder' or coalesce(c.payload->>'status','open')<>'done')
 ), valid as (
   select distinct source,source_id,title,kind,day,activity_id,trip_id,occasion_id from entries
   where day>=p_today and day<=p_today+6
   order by day,source,source_id limit 100
 )
 select coalesce(jsonb_agg(jsonb_build_object(
    'source',source,'id',source_id,'title',title,
    'kind',kind,'event_date',day,'activity_id',activity_id,'trip_id',trip_id,'occasion_id',occasion_id
 ) order by day,source,source_id),'[]'::jsonb) from valid;
$$;

revoke all on function private.reminder_rule_valid(jsonb) from public,anon,authenticated;
revoke all on function private.reminder_next_occurrence(jsonb,timestamptz,timestamptz) from public,anon,authenticated;
revoke all on function private.reminder_quiet_until(uuid,timestamptz) from public,anon,authenticated;
revoke all on function private.reminder_source_closed(text,uuid) from public,anon,authenticated;
