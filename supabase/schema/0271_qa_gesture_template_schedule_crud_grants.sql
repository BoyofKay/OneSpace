-- Reconciled 2026-11-20: applied to QA (ugwrpeduzyzrujkizqfo) on 2026-11-20 from
-- qa/activities-memories-two-scope-cutover-20261120:supabase/schema/0264_qa_gesture_template_schedule_crud_grants.sql (original number 0264). Kept verbatim so the
-- repository replays to the live QA schema. QA only; never apply to Production.
-- QA scoped capabilities for existing sender-only gesture UI. RLS in 0263
-- blocks any cross-account or former-partner access.
GRANT SELECT,INSERT,UPDATE,DELETE ON public.gesture_templates,public.gesture_schedules
 TO authenticated;
DROP POLICY IF EXISTS "QA sender deletes pair schedule" ON public.gesture_schedules;
CREATE POLICY "QA sender deletes pair schedule" ON public.gesture_schedules
 FOR DELETE TO authenticated USING(sender_id=(select auth.uid())
  AND private_space_id IS NULL AND space_id IS NOT NULL AND private.is_space_member(space_id));
