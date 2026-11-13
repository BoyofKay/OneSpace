create table public.activity_attention_snoozes (
 activity_id uuid not null references public.activities(id) on delete cascade,
 component_id uuid,
 user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
 snoozed_until date not null check(snoozed_until between date '2000-01-01' and date '2100-12-31'),
 updated_at timestamptz not null default now(),
 unique nulls not distinct (user_id,activity_id,component_id),
 foreign key(activity_id,component_id) references
   public.activity_components(activity_id,id) on delete cascade
);
create index activity_attention_snoozes_by_user on public.activity_attention_snoozes(user_id,snoozed_until);
alter table public.activity_attention_snoozes enable row level security;
create policy "Read my attention snoozes" on public.activity_attention_snoozes
 for select to authenticated using(user_id=(select auth.uid()) and
   exists(select 1 from public.activities a where a.id=activity_id));
create policy "Snooze own visible Activity or reminder" on public.activity_attention_snoozes
 for insert to authenticated with check(
  user_id=(select auth.uid()) and
  exists(select 1 from public.activities a where a.id=activity_id)
  and (component_id is null or exists(select 1 from public.activity_components c
    where c.activity_id=activity_id and c.id=component_id
    and c.kind='reminder' and c.archived_at is null))
 );
create policy "Update own attention snooze" on public.activity_attention_snoozes
 for update to authenticated
 using(user_id=(select auth.uid()) and
   exists(select 1 from public.activities a where a.id=activity_id))
 with check(user_id=(select auth.uid()) and
   exists(select 1 from public.activities a where a.id=activity_id));
revoke all on public.activity_attention_snoozes from public,anon,authenticated;
grant select on public.activity_attention_snoozes to authenticated;
grant insert(activity_id,component_id,user_id,snoozed_until) on public.activity_attention_snoozes to authenticated;
grant update(snoozed_until) on public.activity_attention_snoozes to authenticated;

CREATE OR REPLACE FUNCTION public.get_home_snapshot_v2(p_today date)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SECURITY INVOKER
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
 'shopping_lists', (select count(*)::int from public.lists l
   where l.space_id=s.id and l.kind='shopping' and l.archived_at is null),
 'other_lists', (select count(*)::int from public.lists l
   where l.space_id=s.id and l.kind='checklist' and l.archived_at is null),
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
$function$;
revoke all on function public.get_home_snapshot_v2(date) from public,anon;
grant execute on function public.get_home_snapshot_v2(date) to authenticated;
CREATE OR REPLACE FUNCTION public.get_remember_overview(p_today date)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
SELECT jsonb_build_object(
 'todo_count', (
   SELECT count(*)::int FROM public.tasks t
   WHERE t.space_id = own.space_id AND t.status = 'open'
 ),
 'notes_count', (
   SELECT count(*)::int FROM public.notes n
   WHERE n.space_id = own.space_id AND n.archived_at IS NULL
 ),
 'event_count', (
   SELECT count(*)::int FROM public.space_events e
   WHERE e.space_id = own.space_id AND e.archived_at IS NULL
 ),
 'upcoming_events', (
   SELECT coalesce(jsonb_agg(jsonb_build_object(
       'id', e.id,
       'title', e.title,
       'event_date', e.event_date,
       'recurrence', e.recurrence,
       'kind', e.kind,
       'visibility', e.visibility
     ) ORDER BY e.event_date, e.title), '[]'::jsonb)
   FROM (
     SELECT ev.id,ev.title,ev.event_date,ev.recurrence,ev.kind,ev.visibility
     FROM public.space_events ev
     WHERE ev.space_id=own.space_id AND ev.archived_at IS NULL
       AND (ev.recurrence='yearly'
         OR ev.event_date BETWEEN p_today AND p_today + 60)
     ORDER BY ev.event_date
     LIMIT 250
   ) e
 ),
 'upcoming_dues', (
   SELECT coalesce(jsonb_agg(jsonb_build_object(
      'id',d.id,
      'title',d.title,
      'type',d.kind,
      'due_on',d.due_on
   ) ORDER BY d.due_on, d.title), '[]'::jsonb)
   FROM (
     SELECT t.id,t.title,'todo'::text AS kind,
       coalesce(t.target_date,t.deadline_at::date) AS due_on
     FROM public.tasks t
     WHERE t.space_id=own.space_id AND t.status='open'
       AND coalesce(t.target_date,t.deadline_at::date) IS NOT NULL
       AND coalesce(t.target_date,t.deadline_at::date) <= p_today + 60
     UNION ALL
     SELECT a.id,a.title,'activity'::text AS kind,a.due_on
     FROM public.activities a
     WHERE a.space_id=own.space_id AND a.archived_at IS NULL
       AND a.stage NOT IN ('completed','cancelled')
       AND a.due_on IS NOT NULL AND a.due_on <= p_today + 60
     UNION ALL
     SELECT c.id,coalesce(nullif(c.label,''),a.title),'reminder'::text,
       CASE WHEN pg_catalog.pg_input_is_valid(c.payload->>'value','date')
         THEN (c.payload->>'value')::date END
     FROM public.activity_components c JOIN public.activities a
       ON a.id=c.activity_id
     WHERE a.space_id=own.space_id AND a.archived_at IS NULL
       AND a.stage NOT IN ('completed','cancelled')
       AND c.kind='reminder' AND c.archived_at IS NULL
       AND coalesce(c.payload->>'status','open')<>'done'
     ORDER BY due_on, title
     LIMIT 20
   ) d
 ),
 'recent_notes', (
   SELECT coalesce(jsonb_agg(jsonb_build_object(
     'id',n.id,'title',n.title,'updated_at',n.updated_at
   ) ORDER BY n.updated_at DESC), '[]'::jsonb)
   FROM (
     SELECT n.id,n.title,n.updated_at
     FROM public.notes n
     WHERE n.space_id=own.space_id AND n.archived_at IS NULL
     ORDER BY n.updated_at DESC LIMIT 4
   ) n
 )
)
FROM public.space_members own
WHERE own.user_id=(SELECT auth.uid())
  AND p_today BETWEEN DATE '2000-01-01' AND DATE '2100-12-31'
LIMIT 1;
$function$;
