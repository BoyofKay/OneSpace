-- Deployed 20261113120053 onespace_r10_unified_seven_day_agenda
-- R10 unified coming-up agenda. RLS enforced by SECURITY INVOKER.
create or replace function public.onespace_annual_date(p_original date,p_today date)
returns date language sql immutable set search_path='' as $$
  with d as (
    select extract(month from p_original)::int as m,
      extract(day from p_original)::int as dy,
      extract(year from p_today)::int as y
  ), this_year as (
    select make_date(y,m,least(dy,
      extract(day from (make_date(y,m,1)+interval '1 month - 1 day'))::int)) as day,
      m,dy,y from d
  )
  select case when day>=p_today then day else
    make_date(y+1,m,least(dy,
      extract(day from (make_date(y+1,m,1)+interval '1 month - 1 day'))::int))
  end from this_year;
$$;

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
      null::uuid as activity_id
   from public.space_events e
   join my_spaces sm on sm.space_id=e.space_id
   where e.archived_at is null
   union all
   select 'todo',t.id::text,t.title,'todo',t.target_date,null::uuid
   from public.tasks t
   join my_spaces sm on sm.space_id=t.space_id
   where t.status='open' and t.target_date is not null
   union all
   select 'activity',a.id::text,a.title,'activity',a.due_on,a.id
   from public.activities a
   join my_spaces sm on sm.space_id=a.space_id
   where a.archived_at is null
     and a.stage not in ('cancelled','completed')
     and a.due_on is not null
   union all
   select 'component',c.id::text,
     coalesce(nullif(c.label,''),a.title),c.kind,
     case when pg_catalog.pg_input_is_valid(c.payload->>'value','date')
       then (c.payload->>'value')::date end, a.id
   from public.activity_components c
   join public.activities a on a.id=c.activity_id
   join my_spaces sm on sm.space_id=a.space_id
   where a.archived_at is null and c.archived_at is null
    and a.stage not in ('cancelled','completed')
    and c.kind in ('date','reminder','countdown')
    and (c.kind<>'reminder' or coalesce(c.payload->>'status','open')<>'done')
 ), valid as (
   select distinct source,source_id,title,kind,day,activity_id from entries
   where day>=p_today and day<=p_today+6
   order by day,source,source_id limit 100
 )
 select coalesce(jsonb_agg(jsonb_build_object(
    'source',source,'id',source_id,'title',title,
    'kind',kind,'event_date',day,'activity_id',activity_id
 ) order by day,source,source_id),'[]'::jsonb) from valid;
$$;
revoke all on function public.onespace_coming_up(date) from public,anon;
grant execute on function public.onespace_coming_up(date) to authenticated;
