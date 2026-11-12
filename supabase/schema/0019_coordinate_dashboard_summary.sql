-- Extend the existing SECURITY INVOKER snapshot with RLS-filtered Coordinate data.\n-- One extra authenticated field per visible space member lets Plans reuse Home's member-name lookup.
-- Still SECURITY INVOKER; rows remain governed by the existing profiles and membership RLS.
-- Extend existing invoker-only Home snapshot without extra API round trips.
CREATE OR REPLACE FUNCTION public.get_home_snapshot()
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
select jsonb_build_object(
 'space_id',s.id,
 'space_name',s.name,
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

