-- QA Only: personal and current-couple Experiences and their reviews, picks, comments, revisions.
-- New scope columns, no legacy migration and no irreversible lifecycle action.
ALTER TABLE public.shared_experiences ADD COLUMN IF NOT EXISTS private_space_id uuid;
ALTER TABLE public.shared_experiences ADD COLUMN IF NOT EXISTS visibility text NOT NULL DEFAULT 'shared';
ALTER TABLE public.shared_experiences ALTER COLUMN space_id DROP NOT NULL;
DO $q$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='public.shared_experiences'::regclass
  AND conname='shared_experiences_personal_scope_fk') THEN
 ALTER TABLE public.shared_experiences ADD CONSTRAINT shared_experiences_personal_scope_fk
 FOREIGN KEY(private_space_id) REFERENCES public.user_private_spaces(owner_id) NOT VALID;
 END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='public.shared_experiences'::regclass
  AND conname='shared_experiences_xor_scope') THEN
 ALTER TABLE public.shared_experiences ADD CONSTRAINT shared_experiences_xor_scope
 CHECK((space_id IS NOT NULL)<>(private_space_id IS NOT NULL)) NOT VALID;
 END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='public.shared_experiences'::regclass
  AND conname='shared_experiences_visibility_scope') THEN
 ALTER TABLE public.shared_experiences ADD CONSTRAINT shared_experiences_visibility_scope
 CHECK((private_space_id IS NULL OR visibility='private') AND visibility IN('private','shared'))
 NOT VALID;
 END IF;
END $q$;
ALTER TABLE public.shared_experiences ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "QA personal Experiences read" ON public.shared_experiences;
CREATE POLICY "QA personal Experiences read" ON public.shared_experiences
 FOR SELECT TO authenticated USING(private_space_id=(select auth.uid())
 AND created_by=(select auth.uid()) AND space_id IS NULL AND visibility='private');
DROP POLICY IF EXISTS "QA personal Experiences insert" ON public.shared_experiences;
CREATE POLICY "QA personal Experiences insert" ON public.shared_experiences
 FOR INSERT TO authenticated WITH CHECK(private_space_id=(select auth.uid())
 AND created_by=(select auth.uid()) AND space_id IS NULL AND visibility='private');
DROP POLICY IF EXISTS "QA personal Experiences update" ON public.shared_experiences;
CREATE POLICY "QA personal Experiences update" ON public.shared_experiences
 FOR UPDATE TO authenticated USING(private_space_id=(select auth.uid())
 AND created_by=(select auth.uid()) AND space_id IS NULL AND visibility='private')
 WITH CHECK(private_space_id=(select auth.uid()) AND created_by=(select auth.uid())
 AND space_id IS NULL AND visibility='private');
DROP POLICY IF EXISTS "QA Experiences valid select scopes" ON public.shared_experiences;
CREATE POLICY "QA Experiences valid select scopes" ON public.shared_experiences
 AS RESTRICTIVE FOR SELECT TO authenticated USING(
 (private_space_id=(select auth.uid()) AND created_by=(select auth.uid())
    AND space_id IS NULL AND visibility='private') OR
 (private_space_id IS NULL AND space_id IS NOT NULL AND visibility='shared'
    AND private.is_space_member(space_id) AND
    (select count(*) FROM public.space_members m WHERE m.space_id=shared_experiences.space_id)=2));
DROP POLICY IF EXISTS "QA Experiences valid insert scopes" ON public.shared_experiences;
CREATE POLICY "QA Experiences valid insert scopes" ON public.shared_experiences
 AS RESTRICTIVE FOR INSERT TO authenticated WITH CHECK(created_by=(select auth.uid()) AND
 ((private_space_id=(select auth.uid()) AND space_id IS NULL AND visibility='private')
 OR (private_space_id IS NULL AND space_id IS NOT NULL AND visibility='shared'
     AND private.is_space_member(space_id) AND
    (select count(*) FROM public.space_members m WHERE m.space_id=shared_experiences.space_id)=2)));
DROP POLICY IF EXISTS "QA Experiences valid update scopes" ON public.shared_experiences;
CREATE POLICY "QA Experiences valid update scopes" ON public.shared_experiences
 AS RESTRICTIVE FOR UPDATE TO authenticated USING(
 (private_space_id=(select auth.uid()) AND created_by=(select auth.uid())
    AND space_id IS NULL AND visibility='private')
 OR (private_space_id IS NULL AND space_id IS NOT NULL AND visibility='shared'
    AND private.is_space_member(space_id) AND
   (select count(*) FROM public.space_members m WHERE m.space_id=shared_experiences.space_id)=2))
 WITH CHECK((private_space_id=(select auth.uid()) AND created_by=(select auth.uid())
    AND space_id IS NULL AND visibility='private')
 OR (private_space_id IS NULL AND space_id IS NOT NULL AND visibility='shared'
    AND private.is_space_member(space_id) AND
   (select count(*) FROM public.space_members m WHERE m.space_id=shared_experiences.space_id)=2));

CREATE OR REPLACE FUNCTION private.qa_experience_scope_guard()
RETURNS trigger LANGUAGE plpgsql SET search_path='' AS $q$
BEGIN
 IF current_user NOT IN ('authenticated','anon') THEN RETURN NEW;END IF;
 IF tg_op='UPDATE' AND (old.space_id IS DISTINCT FROM new.space_id
  OR old.private_space_id IS DISTINCT FROM new.private_space_id
  OR old.created_by IS DISTINCT FROM new.created_by OR
  old.visibility IS DISTINCT FROM new.visibility) THEN
   RAISE EXCEPTION 'Experience ownership cannot change in place' USING ERRCODE='42501';
 END IF;
 IF new.visibility='private' AND (new.space_id IS NOT NULL
   OR new.private_space_id IS DISTINCT FROM auth.uid()
   OR new.created_by IS DISTINCT FROM auth.uid()) THEN
   RAISE EXCEPTION 'Update your app to save personal Experiences in account storage'
      USING ERRCODE='42501';
 END IF;
 RETURN NEW;
END $q$;
REVOKE ALL ON FUNCTION private.qa_experience_scope_guard() FROM public,anon,authenticated;
DROP TRIGGER IF EXISTS zzz_qa_experience_scope_guard ON public.shared_experiences;
CREATE TRIGGER zzz_qa_experience_scope_guard BEFORE INSERT OR UPDATE
 ON public.shared_experiences FOR EACH ROW EXECUTE FUNCTION private.qa_experience_scope_guard();

ALTER TABLE public.shared_experience_comments ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "QA shared_experience_comments personal read" ON public.shared_experience_comments;
CREATE POLICY "QA shared_experience_comments personal read" ON public.shared_experience_comments FOR SELECT TO authenticated
 USING(created_by=(select auth.uid()) AND EXISTS(SELECT 1 FROM public.shared_experiences e
  WHERE e.id=shared_experience_comments.experience_id AND e.private_space_id=(select auth.uid())
  AND e.space_id IS NULL AND e.created_by=(select auth.uid()) AND e.visibility='private'));
DROP POLICY IF EXISTS "QA shared_experience_comments personal insert" ON public.shared_experience_comments;
CREATE POLICY "QA shared_experience_comments personal insert" ON public.shared_experience_comments FOR INSERT TO authenticated
 WITH CHECK(created_by=(select auth.uid()) AND EXISTS(SELECT 1 FROM public.shared_experiences e
  WHERE e.id=shared_experience_comments.experience_id AND e.private_space_id=(select auth.uid())
  AND e.space_id IS NULL AND e.created_by=(select auth.uid()) AND e.visibility='private'));
DROP POLICY IF EXISTS "QA shared_experience_comments personal update" ON public.shared_experience_comments;
CREATE POLICY "QA shared_experience_comments personal update" ON public.shared_experience_comments FOR UPDATE TO authenticated
 USING(created_by=(select auth.uid()) AND EXISTS(SELECT 1 FROM public.shared_experiences e
  WHERE e.id=shared_experience_comments.experience_id AND e.private_space_id=(select auth.uid())
  AND e.space_id IS NULL AND e.created_by=(select auth.uid()) AND e.visibility='private'))
 WITH CHECK(created_by=(select auth.uid()) AND EXISTS(SELECT 1 FROM public.shared_experiences e
  WHERE e.id=shared_experience_comments.experience_id AND e.private_space_id=(select auth.uid())
  AND e.space_id IS NULL AND e.created_by=(select auth.uid()) AND e.visibility='private'));
DROP POLICY IF EXISTS "QA shared_experience_comments parent read isolation" ON public.shared_experience_comments;
CREATE POLICY "QA shared_experience_comments parent read isolation" ON public.shared_experience_comments
 AS RESTRICTIVE FOR SELECT TO authenticated USING(EXISTS(
  SELECT 1 FROM public.shared_experiences e WHERE e.id=shared_experience_comments.experience_id
  AND ((e.private_space_id=(select auth.uid()) AND e.created_by=(select auth.uid())
       AND e.space_id IS NULL AND e.visibility='private' AND shared_experience_comments.created_by=(select auth.uid()))
   OR (e.private_space_id IS NULL AND e.visibility='shared'
       AND private.is_space_member(e.space_id)
       AND (select count(*) FROM public.space_members m WHERE m.space_id=e.space_id)=2))));
DROP POLICY IF EXISTS "QA shared_experience_comments parent insert isolation" ON public.shared_experience_comments;
CREATE POLICY "QA shared_experience_comments parent insert isolation" ON public.shared_experience_comments
 AS RESTRICTIVE FOR INSERT TO authenticated WITH CHECK(created_by=(select auth.uid()) AND EXISTS(
  SELECT 1 FROM public.shared_experiences e WHERE e.id=shared_experience_comments.experience_id
  AND ((e.private_space_id=(select auth.uid()) AND e.created_by=(select auth.uid())
       AND e.space_id IS NULL AND e.visibility='private')
   OR (e.private_space_id IS NULL AND e.visibility='shared'
       AND private.is_space_member(e.space_id)
       AND (select count(*) FROM public.space_members m WHERE m.space_id=e.space_id)=2))));
DROP POLICY IF EXISTS "QA shared_experience_comments parent update isolation" ON public.shared_experience_comments;
CREATE POLICY "QA shared_experience_comments parent update isolation" ON public.shared_experience_comments
 AS RESTRICTIVE FOR UPDATE TO authenticated USING(
  created_by=(select auth.uid()) AND EXISTS(SELECT 1 FROM public.shared_experiences e
   WHERE e.id=shared_experience_comments.experience_id AND ((e.private_space_id=(select auth.uid())
      AND e.created_by=(select auth.uid()) AND e.space_id IS NULL AND e.visibility='private')
     OR(e.private_space_id IS NULL AND e.visibility='shared'
     AND private.is_space_member(e.space_id)
     AND (select count(*) FROM public.space_members m WHERE m.space_id=e.space_id)=2))))
 WITH CHECK(created_by=(select auth.uid()) AND EXISTS(SELECT 1 FROM public.shared_experiences e
   WHERE e.id=shared_experience_comments.experience_id AND ((e.private_space_id=(select auth.uid())
      AND e.created_by=(select auth.uid()) AND e.space_id IS NULL AND e.visibility='private')
     OR(e.private_space_id IS NULL AND e.visibility='shared'
     AND private.is_space_member(e.space_id)
     AND (select count(*) FROM public.space_members m WHERE m.space_id=e.space_id)=2))));

ALTER TABLE public.shared_experience_interests ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "QA shared_experience_interests personal read" ON public.shared_experience_interests;
CREATE POLICY "QA shared_experience_interests personal read" ON public.shared_experience_interests FOR SELECT TO authenticated
 USING(user_id=(select auth.uid()) AND EXISTS(SELECT 1 FROM public.shared_experiences e
  WHERE e.id=shared_experience_interests.experience_id AND e.private_space_id=(select auth.uid())
  AND e.space_id IS NULL AND e.created_by=(select auth.uid()) AND e.visibility='private'));
DROP POLICY IF EXISTS "QA shared_experience_interests personal insert" ON public.shared_experience_interests;
CREATE POLICY "QA shared_experience_interests personal insert" ON public.shared_experience_interests FOR INSERT TO authenticated
 WITH CHECK(user_id=(select auth.uid()) AND EXISTS(SELECT 1 FROM public.shared_experiences e
  WHERE e.id=shared_experience_interests.experience_id AND e.private_space_id=(select auth.uid())
  AND e.space_id IS NULL AND e.created_by=(select auth.uid()) AND e.visibility='private'));
DROP POLICY IF EXISTS "QA shared_experience_interests personal update" ON public.shared_experience_interests;
CREATE POLICY "QA shared_experience_interests personal update" ON public.shared_experience_interests FOR UPDATE TO authenticated
 USING(user_id=(select auth.uid()) AND EXISTS(SELECT 1 FROM public.shared_experiences e
  WHERE e.id=shared_experience_interests.experience_id AND e.private_space_id=(select auth.uid())
  AND e.space_id IS NULL AND e.created_by=(select auth.uid()) AND e.visibility='private'))
 WITH CHECK(user_id=(select auth.uid()) AND EXISTS(SELECT 1 FROM public.shared_experiences e
  WHERE e.id=shared_experience_interests.experience_id AND e.private_space_id=(select auth.uid())
  AND e.space_id IS NULL AND e.created_by=(select auth.uid()) AND e.visibility='private'));
DROP POLICY IF EXISTS "QA shared_experience_interests parent read isolation" ON public.shared_experience_interests;
CREATE POLICY "QA shared_experience_interests parent read isolation" ON public.shared_experience_interests
 AS RESTRICTIVE FOR SELECT TO authenticated USING(EXISTS(
  SELECT 1 FROM public.shared_experiences e WHERE e.id=shared_experience_interests.experience_id
  AND ((e.private_space_id=(select auth.uid()) AND e.created_by=(select auth.uid())
       AND e.space_id IS NULL AND e.visibility='private' AND shared_experience_interests.user_id=(select auth.uid()))
   OR (e.private_space_id IS NULL AND e.visibility='shared'
       AND private.is_space_member(e.space_id)
       AND (select count(*) FROM public.space_members m WHERE m.space_id=e.space_id)=2))));
DROP POLICY IF EXISTS "QA shared_experience_interests parent insert isolation" ON public.shared_experience_interests;
CREATE POLICY "QA shared_experience_interests parent insert isolation" ON public.shared_experience_interests
 AS RESTRICTIVE FOR INSERT TO authenticated WITH CHECK(user_id=(select auth.uid()) AND EXISTS(
  SELECT 1 FROM public.shared_experiences e WHERE e.id=shared_experience_interests.experience_id
  AND ((e.private_space_id=(select auth.uid()) AND e.created_by=(select auth.uid())
       AND e.space_id IS NULL AND e.visibility='private')
   OR (e.private_space_id IS NULL AND e.visibility='shared'
       AND private.is_space_member(e.space_id)
       AND (select count(*) FROM public.space_members m WHERE m.space_id=e.space_id)=2))));
DROP POLICY IF EXISTS "QA shared_experience_interests parent update isolation" ON public.shared_experience_interests;
CREATE POLICY "QA shared_experience_interests parent update isolation" ON public.shared_experience_interests
 AS RESTRICTIVE FOR UPDATE TO authenticated USING(
  user_id=(select auth.uid()) AND EXISTS(SELECT 1 FROM public.shared_experiences e
   WHERE e.id=shared_experience_interests.experience_id AND ((e.private_space_id=(select auth.uid())
      AND e.created_by=(select auth.uid()) AND e.space_id IS NULL AND e.visibility='private')
     OR(e.private_space_id IS NULL AND e.visibility='shared'
     AND private.is_space_member(e.space_id)
     AND (select count(*) FROM public.space_members m WHERE m.space_id=e.space_id)=2))))
 WITH CHECK(user_id=(select auth.uid()) AND EXISTS(SELECT 1 FROM public.shared_experiences e
   WHERE e.id=shared_experience_interests.experience_id AND ((e.private_space_id=(select auth.uid())
      AND e.created_by=(select auth.uid()) AND e.space_id IS NULL AND e.visibility='private')
     OR(e.private_space_id IS NULL AND e.visibility='shared'
     AND private.is_space_member(e.space_id)
     AND (select count(*) FROM public.space_members m WHERE m.space_id=e.space_id)=2))));

ALTER TABLE public.shared_experience_reviews ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "QA shared_experience_reviews personal read" ON public.shared_experience_reviews;
CREATE POLICY "QA shared_experience_reviews personal read" ON public.shared_experience_reviews FOR SELECT TO authenticated
 USING(user_id=(select auth.uid()) AND EXISTS(SELECT 1 FROM public.shared_experiences e
  WHERE e.id=shared_experience_reviews.experience_id AND e.private_space_id=(select auth.uid())
  AND e.space_id IS NULL AND e.created_by=(select auth.uid()) AND e.visibility='private'));
DROP POLICY IF EXISTS "QA shared_experience_reviews personal insert" ON public.shared_experience_reviews;
CREATE POLICY "QA shared_experience_reviews personal insert" ON public.shared_experience_reviews FOR INSERT TO authenticated
 WITH CHECK(user_id=(select auth.uid()) AND EXISTS(SELECT 1 FROM public.shared_experiences e
  WHERE e.id=shared_experience_reviews.experience_id AND e.private_space_id=(select auth.uid())
  AND e.space_id IS NULL AND e.created_by=(select auth.uid()) AND e.visibility='private'));
DROP POLICY IF EXISTS "QA shared_experience_reviews personal update" ON public.shared_experience_reviews;
CREATE POLICY "QA shared_experience_reviews personal update" ON public.shared_experience_reviews FOR UPDATE TO authenticated
 USING(user_id=(select auth.uid()) AND EXISTS(SELECT 1 FROM public.shared_experiences e
  WHERE e.id=shared_experience_reviews.experience_id AND e.private_space_id=(select auth.uid())
  AND e.space_id IS NULL AND e.created_by=(select auth.uid()) AND e.visibility='private'))
 WITH CHECK(user_id=(select auth.uid()) AND EXISTS(SELECT 1 FROM public.shared_experiences e
  WHERE e.id=shared_experience_reviews.experience_id AND e.private_space_id=(select auth.uid())
  AND e.space_id IS NULL AND e.created_by=(select auth.uid()) AND e.visibility='private'));
DROP POLICY IF EXISTS "QA shared_experience_reviews parent read isolation" ON public.shared_experience_reviews;
CREATE POLICY "QA shared_experience_reviews parent read isolation" ON public.shared_experience_reviews
 AS RESTRICTIVE FOR SELECT TO authenticated USING(EXISTS(
  SELECT 1 FROM public.shared_experiences e WHERE e.id=shared_experience_reviews.experience_id
  AND ((e.private_space_id=(select auth.uid()) AND e.created_by=(select auth.uid())
       AND e.space_id IS NULL AND e.visibility='private' AND shared_experience_reviews.user_id=(select auth.uid()))
   OR (e.private_space_id IS NULL AND e.visibility='shared'
       AND private.is_space_member(e.space_id)
       AND (select count(*) FROM public.space_members m WHERE m.space_id=e.space_id)=2))));
DROP POLICY IF EXISTS "QA shared_experience_reviews parent insert isolation" ON public.shared_experience_reviews;
CREATE POLICY "QA shared_experience_reviews parent insert isolation" ON public.shared_experience_reviews
 AS RESTRICTIVE FOR INSERT TO authenticated WITH CHECK(user_id=(select auth.uid()) AND EXISTS(
  SELECT 1 FROM public.shared_experiences e WHERE e.id=shared_experience_reviews.experience_id
  AND ((e.private_space_id=(select auth.uid()) AND e.created_by=(select auth.uid())
       AND e.space_id IS NULL AND e.visibility='private')
   OR (e.private_space_id IS NULL AND e.visibility='shared'
       AND private.is_space_member(e.space_id)
       AND (select count(*) FROM public.space_members m WHERE m.space_id=e.space_id)=2))));
DROP POLICY IF EXISTS "QA shared_experience_reviews parent update isolation" ON public.shared_experience_reviews;
CREATE POLICY "QA shared_experience_reviews parent update isolation" ON public.shared_experience_reviews
 AS RESTRICTIVE FOR UPDATE TO authenticated USING(
  user_id=(select auth.uid()) AND EXISTS(SELECT 1 FROM public.shared_experiences e
   WHERE e.id=shared_experience_reviews.experience_id AND ((e.private_space_id=(select auth.uid())
      AND e.created_by=(select auth.uid()) AND e.space_id IS NULL AND e.visibility='private')
     OR(e.private_space_id IS NULL AND e.visibility='shared'
     AND private.is_space_member(e.space_id)
     AND (select count(*) FROM public.space_members m WHERE m.space_id=e.space_id)=2))))
 WITH CHECK(user_id=(select auth.uid()) AND EXISTS(SELECT 1 FROM public.shared_experiences e
   WHERE e.id=shared_experience_reviews.experience_id AND ((e.private_space_id=(select auth.uid())
      AND e.created_by=(select auth.uid()) AND e.space_id IS NULL AND e.visibility='private')
     OR(e.private_space_id IS NULL AND e.visibility='shared'
     AND private.is_space_member(e.space_id)
     AND (select count(*) FROM public.space_members m WHERE m.space_id=e.space_id)=2))));

ALTER TABLE public.shared_experience_revisions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "QA Experiences revisions follow current parent" ON public.shared_experience_revisions;
CREATE POLICY "QA Experiences revisions follow current parent" ON public.shared_experience_revisions
 AS RESTRICTIVE FOR SELECT TO authenticated USING(EXISTS(SELECT 1 FROM public.shared_experiences e
 WHERE e.id=shared_experience_revisions.experience_id
 AND ((e.private_space_id=(select auth.uid()) AND e.created_by=(select auth.uid())
    AND e.space_id IS NULL AND e.visibility='private')
 OR(e.private_space_id IS NULL AND e.visibility='shared' AND private.is_space_member(e.space_id)
    AND (select count(*) FROM public.space_members m WHERE m.space_id=e.space_id)=2))));
CREATE OR REPLACE FUNCTION private.qa_experience_child_owner_guard()
RETURNS trigger LANGUAGE plpgsql SET search_path='' AS $q$
DECLARE old_author uuid;new_author uuid;
BEGIN
 IF current_user NOT IN ('authenticated','anon') THEN RETURN NEW;END IF;
 IF tg_table_name='shared_experience_comments' THEN
   new_author:=new.created_by;
   IF tg_op='UPDATE' THEN old_author:=old.created_by;END IF;
 ELSE
   new_author:=new.user_id;
   IF tg_op='UPDATE' THEN old_author:=old.user_id;END IF;
 END IF;
 IF tg_op='UPDATE' AND (old.experience_id IS DISTINCT FROM new.experience_id
    OR old_author IS DISTINCT FROM new_author) THEN
  RAISE EXCEPTION 'Cannot transfer experience child owner or parent' USING ERRCODE='42501';
 END IF;
 IF new_author IS DISTINCT FROM auth.uid() THEN
  RAISE EXCEPTION 'Experience child author mismatch' USING ERRCODE='42501';
 END IF;
 RETURN NEW;
END $q$;
REVOKE ALL ON FUNCTION private.qa_experience_child_owner_guard() FROM public,anon,authenticated;

DROP TRIGGER IF EXISTS zzz_qa_experience_child_owner_guard ON public.shared_experience_comments;
CREATE TRIGGER zzz_qa_experience_child_owner_guard BEFORE INSERT OR UPDATE
 ON public.shared_experience_comments FOR EACH ROW EXECUTE FUNCTION private.qa_experience_child_owner_guard();

DROP TRIGGER IF EXISTS zzz_qa_experience_child_owner_guard ON public.shared_experience_interests;
CREATE TRIGGER zzz_qa_experience_child_owner_guard BEFORE INSERT OR UPDATE
 ON public.shared_experience_interests FOR EACH ROW EXECUTE FUNCTION private.qa_experience_child_owner_guard();

DROP TRIGGER IF EXISTS zzz_qa_experience_child_owner_guard ON public.shared_experience_reviews;
CREATE TRIGGER zzz_qa_experience_child_owner_guard BEFORE INSERT OR UPDATE
 ON public.shared_experience_reviews FOR EACH ROW EXECUTE FUNCTION private.qa_experience_child_owner_guard();

DROP POLICY IF EXISTS "QA personal Experience action audit" ON public.record_action_history;
CREATE POLICY "QA personal Experience action audit" ON public.record_action_history
 FOR SELECT TO authenticated USING(record_kind='experience' AND private_space_id=(select auth.uid())
  AND EXISTS(SELECT 1 FROM public.shared_experiences e WHERE e.id=record_id
   AND e.private_space_id=(select auth.uid()) AND e.created_by=(select auth.uid())
   AND e.space_id IS NULL AND e.visibility='private'));
GRANT SELECT,INSERT,UPDATE ON public.shared_experiences,public.shared_experience_comments,
 public.shared_experience_interests,public.shared_experience_reviews TO authenticated;
GRANT SELECT ON public.shared_experience_revisions TO authenticated;
