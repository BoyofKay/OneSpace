-- QA-only regression: two independently owned content scopes, including child.
-- Every test record is rolled back. Production must never run this script.
BEGIN;

SELECT set_config(
  'request.jwt.claim.sub',
  (SELECT owner_id::text FROM public.user_private_spaces ORDER BY owner_id LIMIT 1),
  true
);
SELECT set_config(
  'qa.other_user',
  (SELECT owner_id::text FROM public.user_private_spaces ORDER BY owner_id OFFSET 1 LIMIT 1),
  true
);
SET LOCAL ROLE authenticated;

DO $qa$
DECLARE
  me uuid := auth.uid();
  other_user uuid := current_setting('qa.other_user')::uuid;
  activity_id uuid;
  memory_id uuid;
  component_id uuid;
BEGIN
  IF me IS NULL OR other_user IS NULL OR me = other_user THEN
    RAISE EXCEPTION 'QA needs two distinct existing user-private spaces';
  END IF;

  INSERT INTO public.activities (
    private_space_id, created_by, title, body, visibility
  ) VALUES (
    me, me, 'Rollback-only personal Activity', '', 'private'
  ) RETURNING id INTO activity_id;

  INSERT INTO public.activity_components (
    activity_id, created_by, kind, label, payload
  ) VALUES (
    activity_id, me, 'step', 'Rollback-only child',
    '{"value":"","status":"open"}'::jsonb
  ) RETURNING id INTO component_id;

  INSERT INTO public.memories (
    private_space_id, created_by, title, body, memory_date, visibility
  ) VALUES (
    me, me, 'Rollback-only personal Memory', '', current_date, 'private'
  ) RETURNING id INTO memory_id;

  IF NOT EXISTS (
    SELECT 1 FROM public.activities a
    WHERE a.id = activity_id AND a.private_space_id = me AND a.space_id IS NULL
  ) OR NOT EXISTS (
    SELECT 1 FROM public.activity_components c
    WHERE c.id = component_id AND c.activity_id = activity_id
  ) OR NOT EXISTS (
    SELECT 1 FROM public.memories m
    WHERE m.id = memory_id AND m.private_space_id = me AND m.space_id IS NULL
  ) THEN
    RAISE EXCEPTION 'QA owner cannot read scoped roots and child';
  END IF;

  PERFORM set_config('request.jwt.claim.sub', other_user::text, true);
  IF EXISTS (SELECT 1 FROM public.activities a WHERE a.id = activity_id)
    OR EXISTS (SELECT 1 FROM public.activity_components c WHERE c.id = component_id)
    OR EXISTS (SELECT 1 FROM public.memories m WHERE m.id = memory_id)
  THEN
    RAISE EXCEPTION 'QA cross-account private data leak';
  END IF;

  PERFORM set_config('request.jwt.claim.sub', me::text, true);
  IF NOT EXISTS (SELECT 1 FROM public.activities WHERE id = activity_id)
    OR NOT EXISTS (SELECT 1 FROM public.memories WHERE id = memory_id)
  THEN
    RAISE EXCEPTION 'QA owner lost access after changing user context';
  END IF;
END $qa$;
ROLLBACK;
