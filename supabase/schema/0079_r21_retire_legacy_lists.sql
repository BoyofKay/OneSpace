-- R21: retire empty R8 shopping/list subsystem, keep zero-valued home counters
-- temporarily for compatibility with installed R20 APK snapshots.
CREATE OR REPLACE FUNCTION private.set_object_share(p_type text, p_object uuid, p_active boolean)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_owner uuid := auth.uid(); v_space uuid; v_partner uuid;
begin
 if v_owner is null or p_type not in
  ('task','note','event','memory','goal','checkin')
  or p_object is null or p_active is null then
  raise exception 'Invalid share request';
 end if;
 if p_type='task' then
  select t.space_id into v_space from public.tasks t
   where t.id=p_object and t.created_by=v_owner and t.visibility='private';

elsif p_type='note' then
  select n.space_id into v_space from public.notes n
   where n.id=p_object and n.created_by=v_owner and n.visibility='private';
 elsif p_type='event' then
  select e.space_id into v_space from public.space_events e
   where e.id=p_object and e.created_by=v_owner and e.visibility='private';
 elsif p_type='memory' then
  select m.space_id into v_space from public.memories m
   where m.id=p_object and m.created_by=v_owner and m.visibility='private';
 elsif p_type='goal' then
  select g.space_id into v_space from public.goals g
   where g.id=p_object and g.created_by=v_owner and g.visibility='private';
 elsif p_type='checkin' then
  select c.space_id into v_space from public.daily_checkins c
   where c.id=p_object and c.created_by=v_owner and c.visibility='private';
 end if;
 if v_space is null or not private.is_space_member(v_space) then
  raise exception 'Private item not found or not owned by you';
 end if;
 if not p_active then
  update public.object_shares sh set revoked_at=now()
   where sh.object_type=p_type and sh.object_id=p_object
    and sh.space_id=v_space and sh.shared_by=v_owner
    and sh.revoked_at is null;
  return false;
 end if;
 select m.user_id into v_partner from public.space_members m
  where m.space_id=v_space and m.user_id <> v_owner
  order by m.joined_at limit 1;
 if v_partner is null then raise exception 'No partner is connected'; end if;
 insert into public.object_shares
  (space_id,object_type,object_id,shared_by,shared_with,revoked_at)
 values (v_space,p_type,p_object,v_owner,v_partner,null)
 on conflict(object_type,object_id,shared_with)
 do update set revoked_at=null
 where public.object_shares.shared_by=v_owner
  and public.object_shares.space_id=v_space;
 return true;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.get_home_snapshot()
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
select jsonb_build_object(
 'space_id',s.id,
 'space_name',s.name,
 'relationship_mode',s.relationship_mode,
 'last_met_on',s.last_met_on,
 'next_meet_on',s.next_meet_on,
 'member_count', (select count(*)::int from public.space_members m
                   where m.space_id=s.id),
 'members', (select coalesce(jsonb_agg(jsonb_build_object(
     'user_id',m.user_id,
     'name',coalesce(p.display_name,'Member'),
     'is_me',m.user_id=(select auth.uid())
   ) order by m.joined_at),'[]'::jsonb)
   from public.space_members m left join public.profiles p on p.id=m.user_id
   where m.space_id=s.id),
 'pending_invitation_expires_at',
   (select i.expires_at from public.space_invitations i
     where i.space_id=s.id and i.invited_by=(select auth.uid())
       and i.revoked_at is null and i.accepted_at is null
       and i.expires_at > now() order by i.created_at desc limit 1),
 'open_shared_tasks', (select count(*)::int from public.tasks t
   where t.space_id=s.id and t.visibility='shared' and t.status='open'),
 'assigned_to_me', (select count(*)::int from public.tasks t
   where t.space_id=s.id and t.visibility='shared' and t.status='open'
     and t.assigned_to=(select auth.uid())),
 'my_private_tasks', (select count(*)::int from public.tasks t
   where t.space_id=s.id and t.visibility='private' and t.status='open'
     and t.created_by=(select auth.uid())),
 'completed_shared_tasks', (select count(*)::int from public.tasks t
   where t.space_id=s.id and t.visibility='shared' and t.status='completed'),
 'shopping_lists', 0,
 'other_lists', 0,
 'notes', (select count(*)::int from public.notes n
   where n.space_id=s.id and n.archived_at is null),
 'memories_count', (select count(*)::int from public.memories m
   where m.space_id=s.id and m.archived_at is null),
 'calendar_entries', (select count(*)::int from public.space_events e
   where e.space_id=s.id and e.archived_at is null),
 'active_goals', (select count(*)::int from public.goals g
   where g.space_id=s.id and g.archived_at is null and g.status='active'),
 'completed_goals', (select count(*)::int from public.goals g
   where g.space_id=s.id and g.archived_at is null and g.status='achieved'),
 'recent_checkins', (select count(*)::int from public.daily_checkins c
   where c.space_id=s.id and c.checkin_date >= current_date-interval '7 days'),
 'active_activities', (select count(*)::int from public.activities a
   where a.space_id=s.id and a.archived_at is null
     and a.stage not in ('completed','cancelled')),
 'completed_activities', (select count(*)::int from public.activities a
   where a.space_id=s.id and a.archived_at is null
     and a.stage in ('completed','cancelled')),
 'important_activities', (select count(*)::int from public.activities a
   where a.space_id=s.id and a.archived_at is null
     and a.priority in ('high','urgent')
     and a.stage not in ('completed','cancelled')),
 'upcoming_activities', (select count(*)::int from public.activities a
   where a.space_id=s.id and a.archived_at is null
     and a.stage not in ('completed','cancelled')
     and a.due_on between current_date and current_date+7),
 'recent_activity_comments', (
   select coalesce(jsonb_agg(row_data order by changed_at desc),'[]'::jsonb)
   from (
     select jsonb_build_object(
        'activity_id',a.id,'activity',a.title,
        'message',left(c.body,180),'author',coalesce(p.display_name,'Partner'),
        'created_at',c.created_at) as row_data,
       c.created_at as changed_at
     from public.activity_comments c
     join public.activities a on a.id=c.activity_id
     left join public.profiles p on p.id=c.author_id
     where a.space_id=s.id
     order by c.created_at desc limit 5
   ) recent
 )
)
from public.space_members own
join public.spaces s on s.id=own.space_id
where own.user_id=(select auth.uid())
limit 1;
$function$
;

CREATE OR REPLACE FUNCTION public.get_home_snapshot_v2(p_today date)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
select jsonb_build_object(
 'space_id',s.id,
 'space_name',s.name,
 'relationship_mode',s.relationship_mode,
 'last_met_on',s.last_met_on,
 'next_meet_on',s.next_meet_on,
 'member_count', (select count(*)::int from public.space_members m
                   where m.space_id=s.id),
 'members', (select coalesce(jsonb_agg(jsonb_build_object(
     'user_id',m.user_id,
     'name',coalesce(p.display_name,'Member'),
     'time_zone',p.time_zone,
     'city_weather_shared',p.city_weather_shared,
     'city_name',case when p.city_weather_shared then p.city_name end,
     'temperature_c',case when p.city_weather_shared then p.temperature_c end,
     'weather_code',case when p.city_weather_shared then p.weather_code end,
     'weather_updated_at',case when p.city_weather_shared then p.weather_updated_at end,
     'weather_city_id',case when p.city_weather_shared then p.weather_city_id end,
     'weather_high_c',case when p.city_weather_shared then p.weather_high_c end,
     'weather_low_c',case when p.city_weather_shared then p.weather_low_c end,
     'weather_rain_pct',case when p.city_weather_shared then p.weather_rain_pct end,
     'is_me',m.user_id=(select auth.uid())
   ) order by m.joined_at),'[]'::jsonb)
   from public.space_members m left join public.profiles p on p.id=m.user_id
   where m.space_id=s.id),
 'pending_invitation_expires_at',
   (select i.expires_at from public.space_invitations i
     where i.space_id=s.id and i.invited_by=(select auth.uid())
       and i.revoked_at is null and i.accepted_at is null
       and i.expires_at > now() order by i.created_at desc limit 1),
 'open_shared_tasks', (select count(*)::int from public.tasks t
   where t.space_id=s.id and t.visibility='shared' and t.status='open'),
 'assigned_to_me', (select count(*)::int from public.tasks t
   where t.space_id=s.id and t.visibility='shared' and t.status='open'
     and t.assigned_to=(select auth.uid())),
 'my_private_tasks', (select count(*)::int from public.tasks t
   where t.space_id=s.id and t.visibility='private' and t.status='open'
     and t.created_by=(select auth.uid())),
 'completed_shared_tasks', (select count(*)::int from public.tasks t
   where t.space_id=s.id and t.visibility='shared' and t.status='completed'),
 'shopping_lists', 0,
 'other_lists', 0,
 'notes', (select count(*)::int from public.notes n
   where n.space_id=s.id and n.archived_at is null),
 'memories_count', (select count(*)::int from public.memories m
   where m.space_id=s.id and m.archived_at is null),
 'calendar_entries', (select count(*)::int from public.space_events e
   where e.space_id=s.id and e.archived_at is null),
 'active_goals', (select count(*)::int from public.goals g
   where g.space_id=s.id and g.archived_at is null and g.status='active'),
 'completed_goals', (select count(*)::int from public.goals g
   where g.space_id=s.id and g.archived_at is null and g.status='achieved'),
 'recent_checkins', (select count(*)::int from public.daily_checkins c
   where c.space_id=s.id and c.checkin_date >= p_today-interval '7 days'),
 'active_activities', (select count(*)::int from public.activities a
   where a.space_id=s.id and a.archived_at is null
     and a.stage not in ('completed','cancelled')),
 'completed_activities', (select count(*)::int from public.activities a
   where a.space_id=s.id and a.archived_at is null
     and a.stage in ('completed','cancelled')),
 'important_activities', (select count(*)::int from public.activities a
   where a.space_id=s.id and a.archived_at is null
     and a.priority in ('high','urgent')
     and a.stage not in ('completed','cancelled')),
 'upcoming_activities', (select count(*)::int from public.activities a
   where a.space_id=s.id and a.archived_at is null
     and a.stage not in ('completed','cancelled')
     and a.due_on between p_today and p_today+7),
 'focus_items',(
 select coalesce(jsonb_agg(jsonb_build_object(
  'id',q.id,'activity_id',q.activity_id,'title',q.title,'kind',q.kind,
  'due_on',q.due_on,'priority',q.priority)
  order by q.rank,q.due_on nulls last),'[]'::jsonb)
 from(
   select v.*, case when v.due_on<p_today then 0
    when v.due_on=p_today then 1 when v.kind='reminder' then 2
    when v.priority in ('urgent','high') then 3 else 4 end as rank
   from(
    select a.id,a.id as activity_id,a.title,'activity'::text as kind,a.due_on,a.priority
    from public.activities a
    left join public.activity_attention_snoozes z
     on z.activity_id=a.id and z.component_id is null
       and z.user_id=(select auth.uid())
    where a.space_id=s.id and a.archived_at is null
      and a.stage not in ('completed','cancelled')
      and (a.due_on<=p_today+14 or a.priority in ('high','urgent'))
      and (z.snoozed_until is null or z.snoozed_until<p_today)
    union all
    select c.id,a.id,coalesce(nullif(c.label,''),a.title),
      'reminder'::text,parsed.due_on,a.priority
    from public.activity_components c
    join public.activities a on a.id=c.activity_id
    cross join lateral (
      select case when pg_catalog.pg_input_is_valid(c.payload->>'value','date')
        then (c.payload->>'value')::date end as due_on
    ) parsed
    left join public.activity_attention_snoozes z
     on z.activity_id=a.id and z.component_id=c.id
       and z.user_id=(select auth.uid())
    where a.space_id=s.id and a.archived_at is null
      and a.stage not in ('completed','cancelled')
      and c.archived_at is null and c.kind='reminder'
      and coalesce(c.payload->>'status','open')<>'done'
      and parsed.due_on<=p_today+14
      and (z.snoozed_until is null or z.snoozed_until<p_today)
   ) v order by rank,due_on nulls last limit 14
 ) q
),
'next_events',(
 select coalesce(jsonb_agg(jsonb_build_object(
  'id',e.id,'title',e.title,'event_date',e.event_date,
  'kind',e.kind,'recurrence',e.recurrence)
  order by e.updated_at desc),'[]'::jsonb)
 from(
  select ev.id,ev.title,ev.event_date,ev.kind,ev.recurrence,ev.updated_at
  from public.space_events ev
  where ev.space_id=s.id and ev.archived_at is null
    and (ev.recurrence='yearly'
      or ev.event_date between p_today-1 and p_today+14)
  order by ev.updated_at desc limit 100
 ) e
),
 'recent_activity_comments', (
   select coalesce(jsonb_agg(row_data order by changed_at desc),'[]'::jsonb)
   from (
     select jsonb_build_object(
        'activity_id',a.id,'activity',a.title,
        'message',left(c.body,180),'author',coalesce(p.display_name,'Partner'),
        'created_at',c.created_at) as row_data,
       c.created_at as changed_at
     from public.activity_comments c
     join public.activities a on a.id=c.activity_id
     left join public.profiles p on p.id=c.author_id
     where a.space_id=s.id
     order by c.created_at desc limit 5
   ) recent
 )
)
from public.space_members own
join public.spaces s on s.id=own.space_id
where own.user_id=(select auth.uid())
 and p_today between date '2000-01-01' and date '2100-12-31'
limit 1;
$function$
;

-- The old template RPC is no longer part of the OneSpace product.
drop function if exists public.create_checklist_from_template(uuid,date);
-- No legacy list records or entries exist (verified before this migration).
drop table if exists public.list_items;
drop table if exists public.lists;
