-- QA scoped capabilities for existing sender-only gesture UI. RLS in 0263
-- blocks any cross-account or former-partner access.
GRANT SELECT,INSERT,UPDATE,DELETE ON public.gesture_templates,public.gesture_schedules
 TO authenticated;
DROP POLICY IF EXISTS "QA sender deletes pair schedule" ON public.gesture_schedules;
CREATE POLICY "QA sender deletes pair schedule" ON public.gesture_schedules
 FOR DELETE TO authenticated USING(sender_id=(select auth.uid())
  AND private_space_id IS NULL AND space_id IS NOT NULL AND private.is_space_member(space_id));
