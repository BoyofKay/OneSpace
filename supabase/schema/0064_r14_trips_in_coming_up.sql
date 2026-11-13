-- R14: Add trip starts and itinerary dates to the existing 7-day Today agenda.
-- Does not alter any stored event or trip; SECURITY INVOKER keeps RLS enforced.
create or replace function public.onespace_coming_up(p_today date)
returns jsonb language sql stable security invoker set search_path='' as $$
 with my_spaces as (
   select space_id from public.space_members
   where user_id=(select auth.uid())
 ), entries as (
   select 'calendar'::text as source,e.id::text as source_id,
      e.title,e.kind,
      case when e.recurrence='yearly'
        then public.onespace_annual_date(e.event_date,p_today)
        else e.event_date end as day,
      null::uuid as activity_id,null::uuid as trip_id
   from public.space_events e
   join my_spaces sm on sm.space_id=e.space_id
   where e.archived_at is null
   union all
   select 'todo',t.id::text,t.title,'todo',t.target_date,null::uuid,null::uuid
   from public.tasks t
   join my_spaces sm on sm.space_id=t.space_id
   where t.status='open' and t.target_date is not null
   union all
   select 'experience',e.id::text,e.title,e.category,e.planned_on,null::uuid,null::uuid
   from public.shared_experiences e
   join my_spaces sm on sm.space_id=e.space_id
   where e.archived_at is null and e.status<>'enjoyed' and e.planned_on is not null
   union all
   select 'trip',t.id::text,t.title,'trip',t.start_on,null::uuid,t.id
   from public.shared_trips t
   join my_spaces sm on sm.space_id=t.space_id
   where t.archived_at is null and t.start_on is not null
    and t.status not in ('completed','cancelled')
   union all
   select 'trip_item',i.id::text,i.title,i.kind,i.local_date,null::uuid,t.id
   from public.trip_items i
   join public.shared_trips t on t.id=i.trip_id
   join my_spaces sm on sm.space_id=t.space_id
   where i.archived_at is null and i.done=false and i.local_date is not null
     and t.archived_at is null and t.status not in ('completed','cancelled')
   union all
   select 'activity',a.id::text,a.title,'activity',a.due_on,a.id,null::uuid
   from public.activities a
   join my_spaces sm on sm.space_id=a.space_id
   where a.archived_at is null
     and a.stage not in ('cancelled','completed')
     and a.due_on is not null
   union all
   select 'component',c.id::text,
     coalesce(nullif(c.label,''),a.title),c.kind,
     case when pg_catalog.pg_input_is_valid(c.payload->>'value','date')
       then (c.payload->>'value')::date end, a.id,null::uuid
   from public.activity_components c
   join public.activities a on a.id=c.activity_id
   join my_spaces sm on sm.space_id=a.space_id
   where a.archived_at is null and c.archived_at is null
    and a.stage not in ('cancelled','completed')
    and c.kind in ('date','reminder','countdown')
    and (c.kind<>'reminder' or coalesce(c.payload->>'status','open')<>'done')
 ), valid as (
   select distinct source,source_id,title,kind,day,activity_id,trip_id from entries
   where day>=p_today and day<=p_today+6
   order by day,source,source_id limit 100
 )
 select coalesce(jsonb_agg(jsonb_build_object(
    'source',source,'id',source_id,'title',title,
    'kind',kind,'event_date',day,'activity_id',activity_id,'trip_id',trip_id
 ) order by day,source,source_id),'[]'::jsonb) from valid;
$$;
revoke all on function public.onespace_coming_up(date) from public,anon;
grant execute on function public.onespace_coming_up(date) to authenticated;
