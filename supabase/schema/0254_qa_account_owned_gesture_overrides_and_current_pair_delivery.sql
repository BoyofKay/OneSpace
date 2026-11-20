-- QA only. Reusable custom-message overrides belong to account, not couple.
-- Sent gestures are strictly scoped to a live two-member relationship.
ALTER TABLE public.gesture_message_overrides ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "QA account reads gesture preferences" ON public.gesture_message_overrides;
CREATE POLICY "QA account reads gesture preferences" ON public.gesture_message_overrides
 FOR SELECT TO authenticated
 USING(private_space_id=(select auth.uid()) AND owner_id=(select auth.uid()) AND space_id IS NULL);
DROP POLICY IF EXISTS "QA account creates gesture preferences" ON public.gesture_message_overrides;
CREATE POLICY "QA account creates gesture preferences" ON public.gesture_message_overrides
 FOR INSERT TO authenticated
 WITH CHECK(private_space_id=(select auth.uid()) AND owner_id=(select auth.uid()) AND space_id IS NULL);
DROP POLICY IF EXISTS "QA account updates gesture preferences" ON public.gesture_message_overrides;
CREATE POLICY "QA account updates gesture preferences" ON public.gesture_message_overrides
 FOR UPDATE TO authenticated
 USING(private_space_id=(select auth.uid()) AND owner_id=(select auth.uid()) AND space_id IS NULL)
 WITH CHECK(private_space_id=(select auth.uid()) AND owner_id=(select auth.uid()) AND space_id IS NULL);
DROP POLICY IF EXISTS "QA gesture preference owners only" ON public.gesture_message_overrides;
CREATE POLICY "QA gesture preference owners only" ON public.gesture_message_overrides
 AS RESTRICTIVE FOR SELECT TO authenticated USING(
  private_space_id=(select auth.uid()) AND owner_id=(select auth.uid()) AND space_id IS NULL);
DROP POLICY IF EXISTS "QA gesture preference owner insert" ON public.gesture_message_overrides;
CREATE POLICY "QA gesture preference owner insert" ON public.gesture_message_overrides
 AS RESTRICTIVE FOR INSERT TO authenticated WITH CHECK(
  private_space_id=(select auth.uid()) AND owner_id=(select auth.uid()) AND space_id IS NULL);
DROP POLICY IF EXISTS "QA gesture preference owner update" ON public.gesture_message_overrides;
CREATE POLICY "QA gesture preference owner update" ON public.gesture_message_overrides
 AS RESTRICTIVE FOR UPDATE TO authenticated
 USING(private_space_id=(select auth.uid()) AND owner_id=(select auth.uid()) AND space_id IS NULL)
 WITH CHECK(private_space_id=(select auth.uid()) AND owner_id=(select auth.uid()) AND space_id IS NULL);

CREATE OR REPLACE FUNCTION private.qa_gesture_override_owner_guard()
RETURNS trigger LANGUAGE plpgsql SET search_path='' AS $q$
BEGIN
 IF current_user NOT IN ('authenticated','anon') THEN RETURN NEW;END IF;
 IF tg_op='UPDATE' AND (
   old.private_space_id IS DISTINCT FROM new.private_space_id OR
   old.space_id IS DISTINCT FROM new.space_id OR
   old.owner_id IS DISTINCT FROM new.owner_id) THEN
   RAISE EXCEPTION 'Cannot move gesture preferences to another owner or space'
     USING ERRCODE='42501';
 END IF;
 IF new.private_space_id IS DISTINCT FROM auth.uid() OR
    new.owner_id IS DISTINCT FROM auth.uid() OR new.space_id IS NOT NULL THEN
   RAISE EXCEPTION 'Gesture customizations must be saved in your personal space'
     USING ERRCODE='42501';
 END IF;
 RETURN NEW;
END $q$;
REVOKE ALL ON FUNCTION private.qa_gesture_override_owner_guard() FROM public,anon,authenticated;
DROP TRIGGER IF EXISTS qa_gesture_override_owner_guard ON public.gesture_message_overrides;
CREATE TRIGGER qa_gesture_override_owner_guard BEFORE INSERT OR UPDATE
 ON public.gesture_message_overrides FOR EACH ROW
 EXECUTE FUNCTION private.qa_gesture_override_owner_guard();

-- Delivered gestures cannot be created for a former pair, or sender/recipient
-- claims substituted into another two-person couple. Delivery history erases
-- with the shared space, not either personal account.
ALTER TABLE public.partner_gestures ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "QA delivered gestures select current couple" ON public.partner_gestures;
CREATE POLICY "QA delivered gestures select current couple" ON public.partner_gestures
 AS RESTRICTIVE FOR SELECT TO authenticated USING(
   private.is_space_member(space_id)
   AND (sender_id=(select auth.uid()) OR recipient_id=(select auth.uid()))
   AND (SELECT count(*) FROM public.space_members sm WHERE sm.space_id=partner_gestures.space_id)=2);
DROP POLICY IF EXISTS "QA delivered gestures insert current couple" ON public.partner_gestures;
CREATE POLICY "QA delivered gestures insert current couple" ON public.partner_gestures
 AS RESTRICTIVE FOR INSERT TO authenticated WITH CHECK(
 sender_id=(select auth.uid()) AND recipient_id<>(select auth.uid())
 AND private.is_space_member(space_id)
 AND EXISTS(SELECT 1 FROM public.space_members m
    WHERE m.space_id=partner_gestures.space_id AND m.user_id=partner_gestures.recipient_id)
 AND (SELECT count(*) FROM public.space_members sm WHERE sm.space_id=partner_gestures.space_id)=2
 AND (gesture_schedule_id IS NULL OR EXISTS(
    SELECT 1 FROM public.gesture_schedules gs
    WHERE gs.id=partner_gestures.gesture_schedule_id
      AND gs.space_id=partner_gestures.space_id
      AND gs.sender_id=partner_gestures.sender_id
      AND gs.recipient_id=partner_gestures.recipient_id)));
-- Legacy partner-specific templates and automated schedules retain their old
-- paired scope until their recipient-linked state and crons are redesigned.
GRANT SELECT,INSERT,UPDATE ON public.gesture_message_overrides TO authenticated;
GRANT SELECT,INSERT ON public.partner_gestures TO authenticated;
