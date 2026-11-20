-- Reconciled 2026-11-20: applied to QA (ugwrpeduzyzrujkizqfo) on 2026-11-20 from
-- qa/activities-memories-two-scope-cutover-20261120:supabase/schema/0263_qa_pair_only_gesture_templates_and_schedules.sql (original number 0263). Kept verbatim so the
-- repository replays to the live QA schema. QA only; never apply to Production.
-- QA: recipient-addressed gesture templates and automation schedules are
-- RELATIONSHIP-OWNED, not personal. Reusable message overrides are separately
-- account-owned (0254). A future partner must never receive old pair messages.

ALTER TABLE public.gesture_templates ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "QA gesture_templates live pair owner read" ON public.gesture_templates;
CREATE POLICY "QA gesture_templates live pair owner read" ON public.gesture_templates
 AS RESTRICTIVE FOR SELECT TO authenticated USING(private_space_id IS NULL AND space_id IS NOT NULL
 AND creator_id=(select auth.uid()) AND recipient_id<>(select auth.uid())
 AND private.is_space_member(space_id)
 AND EXISTS(SELECT 1 FROM public.space_members m
   WHERE m.space_id=gesture_templates.space_id AND m.user_id=gesture_templates.recipient_id)
 AND (SELECT count(*) FROM public.space_members m WHERE m.space_id=gesture_templates.space_id)=2);
DROP POLICY IF EXISTS "QA gesture_templates live pair owner insert" ON public.gesture_templates;
CREATE POLICY "QA gesture_templates live pair owner insert" ON public.gesture_templates
 AS RESTRICTIVE FOR INSERT TO authenticated WITH CHECK(private_space_id IS NULL AND space_id IS NOT NULL
 AND creator_id=(select auth.uid()) AND recipient_id<>(select auth.uid())
 AND private.is_space_member(space_id)
 AND EXISTS(SELECT 1 FROM public.space_members m
   WHERE m.space_id=gesture_templates.space_id AND m.user_id=gesture_templates.recipient_id)
 AND (SELECT count(*) FROM public.space_members m WHERE m.space_id=gesture_templates.space_id)=2);
DROP POLICY IF EXISTS "QA gesture_templates live pair owner update" ON public.gesture_templates;
CREATE POLICY "QA gesture_templates live pair owner update" ON public.gesture_templates
 AS RESTRICTIVE FOR UPDATE TO authenticated USING(private_space_id IS NULL AND space_id IS NOT NULL
 AND creator_id=(select auth.uid()) AND recipient_id<>(select auth.uid())
 AND private.is_space_member(space_id)
 AND EXISTS(SELECT 1 FROM public.space_members m
   WHERE m.space_id=gesture_templates.space_id AND m.user_id=gesture_templates.recipient_id)
 AND (SELECT count(*) FROM public.space_members m WHERE m.space_id=gesture_templates.space_id)=2) WITH CHECK(private_space_id IS NULL AND space_id IS NOT NULL
 AND creator_id=(select auth.uid()) AND recipient_id<>(select auth.uid())
 AND private.is_space_member(space_id)
 AND EXISTS(SELECT 1 FROM public.space_members m
   WHERE m.space_id=gesture_templates.space_id AND m.user_id=gesture_templates.recipient_id)
 AND (SELECT count(*) FROM public.space_members m WHERE m.space_id=gesture_templates.space_id)=2);
DROP POLICY IF EXISTS "QA gesture_templates live pair owner delete" ON public.gesture_templates;
CREATE POLICY "QA gesture_templates live pair owner delete" ON public.gesture_templates
 AS RESTRICTIVE FOR DELETE TO authenticated USING(private_space_id IS NULL AND space_id IS NOT NULL
 AND creator_id=(select auth.uid()) AND recipient_id<>(select auth.uid())
 AND private.is_space_member(space_id)
 AND EXISTS(SELECT 1 FROM public.space_members m
   WHERE m.space_id=gesture_templates.space_id AND m.user_id=gesture_templates.recipient_id)
 AND (SELECT count(*) FROM public.space_members m WHERE m.space_id=gesture_templates.space_id)=2);

ALTER TABLE public.gesture_schedules ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "QA gesture_schedules live pair owner read" ON public.gesture_schedules;
CREATE POLICY "QA gesture_schedules live pair owner read" ON public.gesture_schedules
 AS RESTRICTIVE FOR SELECT TO authenticated USING(private_space_id IS NULL AND space_id IS NOT NULL
 AND sender_id=(select auth.uid()) AND recipient_id<>(select auth.uid())
 AND private.is_space_member(space_id)
 AND EXISTS(SELECT 1 FROM public.space_members m
   WHERE m.space_id=gesture_schedules.space_id AND m.user_id=gesture_schedules.recipient_id)
 AND (SELECT count(*) FROM public.space_members m WHERE m.space_id=gesture_schedules.space_id)=2);
DROP POLICY IF EXISTS "QA gesture_schedules live pair owner insert" ON public.gesture_schedules;
CREATE POLICY "QA gesture_schedules live pair owner insert" ON public.gesture_schedules
 AS RESTRICTIVE FOR INSERT TO authenticated WITH CHECK(private_space_id IS NULL AND space_id IS NOT NULL
 AND sender_id=(select auth.uid()) AND recipient_id<>(select auth.uid())
 AND private.is_space_member(space_id)
 AND EXISTS(SELECT 1 FROM public.space_members m
   WHERE m.space_id=gesture_schedules.space_id AND m.user_id=gesture_schedules.recipient_id)
 AND (SELECT count(*) FROM public.space_members m WHERE m.space_id=gesture_schedules.space_id)=2);
DROP POLICY IF EXISTS "QA gesture_schedules live pair owner update" ON public.gesture_schedules;
CREATE POLICY "QA gesture_schedules live pair owner update" ON public.gesture_schedules
 AS RESTRICTIVE FOR UPDATE TO authenticated USING(private_space_id IS NULL AND space_id IS NOT NULL
 AND sender_id=(select auth.uid()) AND recipient_id<>(select auth.uid())
 AND private.is_space_member(space_id)
 AND EXISTS(SELECT 1 FROM public.space_members m
   WHERE m.space_id=gesture_schedules.space_id AND m.user_id=gesture_schedules.recipient_id)
 AND (SELECT count(*) FROM public.space_members m WHERE m.space_id=gesture_schedules.space_id)=2) WITH CHECK(private_space_id IS NULL AND space_id IS NOT NULL
 AND sender_id=(select auth.uid()) AND recipient_id<>(select auth.uid())
 AND private.is_space_member(space_id)
 AND EXISTS(SELECT 1 FROM public.space_members m
   WHERE m.space_id=gesture_schedules.space_id AND m.user_id=gesture_schedules.recipient_id)
 AND (SELECT count(*) FROM public.space_members m WHERE m.space_id=gesture_schedules.space_id)=2);
DROP POLICY IF EXISTS "QA gesture_schedules live pair owner delete" ON public.gesture_schedules;
CREATE POLICY "QA gesture_schedules live pair owner delete" ON public.gesture_schedules
 AS RESTRICTIVE FOR DELETE TO authenticated USING(private_space_id IS NULL AND space_id IS NOT NULL
 AND sender_id=(select auth.uid()) AND recipient_id<>(select auth.uid())
 AND private.is_space_member(space_id)
 AND EXISTS(SELECT 1 FROM public.space_members m
   WHERE m.space_id=gesture_schedules.space_id AND m.user_id=gesture_schedules.recipient_id)
 AND (SELECT count(*) FROM public.space_members m WHERE m.space_id=gesture_schedules.space_id)=2);

CREATE OR REPLACE FUNCTION private.qa_recipient_gesture_immutable()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $q$
DECLARE author_id uuid;
BEGIN
 IF current_user NOT IN ('authenticated','anon') THEN RETURN new;END IF;
 IF tg_table_name='gesture_templates' THEN
  author_id:=new.creator_id;
  IF tg_op='UPDATE' AND (
   new.creator_id IS DISTINCT FROM old.creator_id OR
   new.recipient_id IS DISTINCT FROM old.recipient_id OR
   new.space_id IS DISTINCT FROM old.space_id OR
   new.private_space_id IS DISTINCT FROM old.private_space_id) THEN
   RAISE EXCEPTION 'Cannot readdress or relocate partner gesture templates'
    USING ERRCODE='42501';
  END IF;
 ELSE
  author_id:=new.sender_id;
  IF tg_op='UPDATE' AND (
   new.sender_id IS DISTINCT FROM old.sender_id OR
   new.recipient_id IS DISTINCT FROM old.recipient_id OR
   new.space_id IS DISTINCT FROM old.space_id OR
   new.private_space_id IS DISTINCT FROM old.private_space_id) THEN
   RAISE EXCEPTION 'Cannot readdress or relocate gesture schedules'
    USING ERRCODE='42501';
  END IF;
 END IF;
 IF author_id IS DISTINCT FROM auth.uid() OR new.private_space_id IS NOT NULL
  OR new.space_id IS NULL OR NOT private.is_space_member(new.space_id)
  OR NOT EXISTS(SELECT 1 FROM public.space_members m
     WHERE m.space_id=new.space_id AND m.user_id=new.recipient_id)
  OR (SELECT count(*) FROM public.space_members m WHERE m.space_id=new.space_id)<>2 THEN
   RAISE EXCEPTION 'Partner-addressed gestures require current two-member couple'
    USING ERRCODE='42501';
 END IF;
 RETURN new;
END $q$;
REVOKE ALL ON FUNCTION private.qa_recipient_gesture_immutable() FROM PUBLIC,anon,authenticated;
DROP TRIGGER IF EXISTS zzz_qa_recipient_gesture_guard ON public.gesture_templates;
CREATE TRIGGER zzz_qa_recipient_gesture_guard BEFORE INSERT OR UPDATE
 ON public.gesture_templates FOR EACH ROW
 EXECUTE FUNCTION private.qa_recipient_gesture_immutable();
DROP TRIGGER IF EXISTS zzz_qa_recipient_gesture_guard ON public.gesture_schedules;
CREATE TRIGGER zzz_qa_recipient_gesture_guard BEFORE INSERT OR UPDATE
 ON public.gesture_schedules FOR EACH ROW
 EXECUTE FUNCTION private.qa_recipient_gesture_immutable();
