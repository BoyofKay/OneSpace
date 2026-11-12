-- Remember: one RLS-respecting request for quick links and upcoming items.
-- Dates are evaluated in the viewer's local calendar, supplied by Flutter.
CREATE OR REPLACE FUNCTION public.get_remember_overview(p_today date)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = ''
AS $$
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
$$;
REVOKE ALL ON FUNCTION public.get_remember_overview(date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_remember_overview(date) TO authenticated;