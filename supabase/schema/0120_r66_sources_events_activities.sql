-- R66: reminders can point at activities, trips and notes; activities get
-- "belongs to"; events get a location and the reminders' repeat rule.

-- 1) Activities: who it belongs to (a member of the space, or nobody = both).
alter table public.activities add column if not exists for_user_id uuid references auth.users(id) on delete set null;
create or replace function private.activity_for_user_is_member()
returns trigger language plpgsql security definer set search_path to '' as $$
begin
  if new.for_user_id is not null and not exists(select 1 from public.space_members m
      where m.space_id=new.space_id and m.user_id=new.for_user_id) then
    raise exception 'That person is not in this space';
  end if;
  return new;
end $$;
drop trigger if exists activities_for_user_member on public.activities;
create trigger activities_for_user_member before insert or update of for_user_id,space_id on public.activities
  for each row execute function private.activity_for_user_is_member();

-- 2) Events: location and full repeat rule (same JSON as reminders.repeat_rule).
alter table public.space_events add column if not exists location text;
alter table public.space_events add column if not exists repeat_rule jsonb;
do $$ begin
  alter table public.space_events add constraint space_events_location_check check (location is null or char_length(location) <= 300);
exception when duplicate_object then null; end $$;
do $$ begin
  alter table public.space_events add constraint space_events_repeat_rule_shape
    check (repeat_rule is null or (jsonb_typeof(repeat_rule)='object' and length(repeat_rule::text) <= 1200));
exception when duplicate_object then null; end $$;

-- Next day (>= p_from) an event happens: one-off, yearly, or by repeat_rule.
create or replace function public.onespace_event_next_on(p_start date, p_recurrence text, p_rule jsonb, p_from date)
returns date language plpgsql stable set search_path to '' as $$
declare d date; freq text; n int; untl date; days int[]; i int;
begin
  if p_start is null then return null; end if;
  if p_rule is null then
    if p_recurrence = 'yearly' then return public.onespace_annual_date(p_start, p_from); end if;
    return case when p_start >= p_from then p_start else null end;
  end if;
  freq := coalesce(p_rule->>'freq','none');
  n := greatest(coalesce((p_rule->>'interval')::int,1),1);
  untl := nullif(p_rule->>'until','')::date;
  select coalesce(array_agg(x::int),'{}') into days from jsonb_array_elements_text(coalesce(p_rule->'weekdays','[]'::jsonb)) x;
  d := greatest(p_start, p_from);
  for i in 0..800 loop
    exit when untl is not null and d > untl;
    if (freq='daily' and (d - p_start) % n = 0)
      or (freq='weekly' and (extract(isodow from d)::int = any(case when cardinality(days)=0 then array[extract(isodow from p_start)::int] else days end))
          and (((d - extract(isodow from d)::int) - (p_start - extract(isodow from p_start)::int)) / 7) % n = 0)
      or (freq='monthly' and extract(day from d)=extract(day from p_start)
          and ((extract(year from d)-extract(year from p_start))*12 + extract(month from d)-extract(month from p_start))::int % n = 0)
      or (freq='yearly' and extract(day from d)=extract(day from p_start) and extract(month from d)=extract(month from p_start)
          and (extract(year from d)-extract(year from p_start))::int % n = 0)
    then return d; end if;
    d := d + 1;
  end loop;
  return null;
end $$;
revoke all on function public.onespace_event_next_on(date,text,jsonb,date) from public, anon;
grant execute on function public.onespace_event_next_on(date,text,jsonb,date) to authenticated;

-- 3) Reminder sources: activity, trip, note.
alter table public.reminders drop constraint if exists reminders_source_kind_check;
alter table public.reminders add constraint reminders_source_kind_check
  check (source_kind = any (array['task','calendar','occasion','activity','trip','note']));

create or replace function private.reminder_validate_source()
returns trigger language plpgsql security definer set search_path to '' as $function$
declare allowed boolean:=false;
begin
 if new.source_kind is null then return new; end if;
 if new.source_kind='task' then
  select exists(select 1 from public.tasks t
   where t.id=new.source_id and t.space_id=new.space_id and t.migrated_to_list is null
    and (t.visibility='shared' or (new.visibility='private' and t.created_by=new.created_by))) into allowed;
 elsif new.source_kind='calendar' then
  select exists(select 1 from public.space_events e
   where e.id=new.source_id and e.space_id=new.space_id and e.archived_at is null
    and (e.visibility='shared' or (new.visibility='private' and e.created_by=new.created_by))) into allowed;
 elsif new.source_kind='occasion' then
  select exists(select 1 from public.occasion_plans o
   where o.id=new.source_id and o.space_id=new.space_id and o.archived_at is null
    and (o.visibility='shared' or (new.visibility='private' and o.created_by=new.created_by))) into allowed;
 elsif new.source_kind='activity' then
  select exists(select 1 from public.activities a
   where a.id=new.source_id and a.space_id=new.space_id and a.archived_at is null
    and (a.visibility='shared' or (new.visibility='private' and a.created_by=new.created_by))) into allowed;
 elsif new.source_kind='trip' then
  select exists(select 1 from public.shared_trips t
   where t.id=new.source_id and t.space_id=new.space_id and t.archived_at is null
    and (t.visibility='shared' or (new.visibility='private' and t.created_by=new.created_by))) into allowed;
 elsif new.source_kind='note' then
  select exists(select 1 from public.notes n
   where n.id=new.source_id and n.space_id=new.space_id and n.archived_at is null
    and (n.visibility='shared' or (new.visibility='private' and n.created_by=new.created_by))) into allowed;
 end if;
 if not allowed then
  raise exception 'Linked item unavailable or not visible to reminder recipients';
 end if;
 return new;
end $function$;

create or replace function private.reminder_source_closed(p_kind text, p_id uuid)
returns boolean language sql stable security definer set search_path to '' as $function$
 select case p_kind
  when 'task' then not exists(select 1 from public.tasks t where t.id=p_id and t.status='open')
  when 'calendar' then not exists(select 1 from public.space_events e where e.id=p_id and e.archived_at is null)
  when 'occasion' then not exists(select 1 from public.occasion_plans o
     where o.id=p_id and o.archived_at is null and o.status not in ('celebrated','cancelled'))
  when 'activity' then not exists(select 1 from public.activities a
     where a.id=p_id and a.archived_at is null and a.stage not in ('completed','cancelled'))
  when 'trip' then not exists(select 1 from public.shared_trips t
     where t.id=p_id and t.archived_at is null and t.status not in ('completed','cancelled'))
  when 'note' then not exists(select 1 from public.notes n where n.id=p_id and n.archived_at is null)
  else false end;
$function$;

-- 4) Today / Remember / Coming up understand repeating events.
do $m$
declare d text;
begin
  select pg_get_functiondef('public.get_home_snapshot_v2'::regproc) into d;
  if position('repeat_rule' in d)=0 then
    d:=replace(d, $x$'kind',e.kind,'recurrence',e.recurrence)$x$, $x$'kind',e.kind,'recurrence',e.recurrence,'repeat_rule',e.repeat_rule)$x$);
    d:=replace(d, $x$select ev.id,ev.title,ev.event_date,ev.kind,ev.recurrence,ev.updated_at$x$, $x$select ev.id,ev.title,ev.event_date,ev.kind,ev.recurrence,ev.repeat_rule,ev.updated_at$x$);
    d:=replace(d, $x$(ev.recurrence='yearly'$x$, $x$(ev.recurrence='yearly' or ev.repeat_rule is not null$x$);
    execute d;
  end if;
  select pg_get_functiondef('public.get_remember_overview'::regproc) into d;
  if position('repeat_rule' in d)=0 then
    d:=replace(d, $x$'recurrence', e.recurrence,$x$, $x$'recurrence', e.recurrence,
       'repeat_rule', e.repeat_rule,$x$);
    d:=replace(d, $x$SELECT ev.id,ev.title,ev.event_date,ev.recurrence,ev.kind,ev.visibility$x$, $x$SELECT ev.id,ev.title,ev.event_date,ev.recurrence,ev.repeat_rule,ev.kind,ev.visibility$x$);
    d:=replace(d, $x$(ev.recurrence='yearly'$x$, $x$(ev.recurrence='yearly' OR ev.repeat_rule IS NOT NULL$x$);
    execute d;
  end if;
  select pg_get_functiondef('public.onespace_coming_up'::regproc) into d;
  if position('onespace_event_next_on' in d)=0 then
    d:=replace(d, $x$case when e.recurrence='yearly'
        then public.onespace_annual_date(e.event_date,p_today)
        else e.event_date end as day,$x$, $x$public.onespace_event_next_on(e.event_date,e.recurrence,e.repeat_rule,p_today) as day,$x$);
    execute d;
  end if;
end $m$;
