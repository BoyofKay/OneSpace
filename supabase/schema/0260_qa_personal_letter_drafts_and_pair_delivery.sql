-- Reconciled 2026-11-20: applied to QA (ugwrpeduzyzrujkizqfo) on 2026-11-20 from
-- qa/activities-memories-two-scope-cutover-20261120:supabase/schema/0253_qa_personal_letter_drafts_and_pair_delivery.sql (original number 0253). Kept verbatim so the
-- repository replays to the live QA schema. QA only; never apply to Production.
-- QA: account-owned unsent letter drafts, separate current-pair sent letters.
-- Draft-to-sent is forbidden within an account scope; sending a COPY
-- must insert a new shared letter. Legacy data migration is separate.
ALTER TABLE public.couple_letters ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "QA account owner sees personal letter drafts" ON public.couple_letters;
CREATE POLICY "QA account owner sees personal letter drafts" ON public.couple_letters
 FOR SELECT TO authenticated
 USING(private_space_id=(select auth.uid()) AND author_id=(select auth.uid())
  AND status='draft' AND space_id IS NULL AND reply_to IS NULL);
DROP POLICY IF EXISTS "QA account owner creates personal letter drafts" ON public.couple_letters;
CREATE POLICY "QA account owner creates personal letter drafts" ON public.couple_letters
 FOR INSERT TO authenticated
 WITH CHECK(private_space_id=(select auth.uid()) AND author_id=(select auth.uid())
  AND status='draft' AND space_id IS NULL AND reply_to IS NULL);
DROP POLICY IF EXISTS "QA account owner edits personal letter drafts" ON public.couple_letters;
CREATE POLICY "QA account owner edits personal letter drafts" ON public.couple_letters
 FOR UPDATE TO authenticated
 USING(private_space_id=(select auth.uid()) AND author_id=(select auth.uid())
  AND status='draft' AND space_id IS NULL AND reply_to IS NULL)
 WITH CHECK(private_space_id=(select auth.uid()) AND author_id=(select auth.uid())
  AND status='draft' AND space_id IS NULL AND reply_to IS NULL);
DROP POLICY IF EXISTS "QA account owner deletes personal letter drafts" ON public.couple_letters;
CREATE POLICY "QA account owner deletes personal letter drafts" ON public.couple_letters
 FOR DELETE TO authenticated
 USING(private_space_id=(select auth.uid()) AND author_id=(select auth.uid())
  AND status='draft' AND space_id IS NULL AND reply_to IS NULL);

DROP POLICY IF EXISTS "QA letter current pairing read scope" ON public.couple_letters;
CREATE POLICY "QA letter current pairing read scope" ON public.couple_letters
 AS RESTRICTIVE FOR SELECT TO authenticated
 USING(
 (private_space_id=(select auth.uid()) AND author_id=(select auth.uid())
  AND status='draft' AND space_id IS NULL AND reply_to IS NULL)
 OR
 (private_space_id IS NULL AND space_id IS NOT NULL
  AND private.is_space_member(space_id)
  AND (SELECT count(*) FROM public.space_members sm WHERE sm.space_id=couple_letters.space_id)=2)
 );
DROP POLICY IF EXISTS "QA letter private or paired insert only" ON public.couple_letters;
CREATE POLICY "QA letter private or paired insert only" ON public.couple_letters
 AS RESTRICTIVE FOR INSERT TO authenticated WITH CHECK(
 (private_space_id=(select auth.uid()) AND author_id=(select auth.uid())
  AND status='draft' AND space_id IS NULL AND reply_to IS NULL)
 OR
 (private_space_id IS NULL AND space_id IS NOT NULL
  AND author_id=(select auth.uid()) AND private.is_space_member(space_id)
  AND (SELECT count(*) FROM public.space_members sm WHERE sm.space_id=couple_letters.space_id)=2)
 );
DROP POLICY IF EXISTS "QA letter private or paired update only" ON public.couple_letters;
CREATE POLICY "QA letter private or paired update only" ON public.couple_letters
 AS RESTRICTIVE FOR UPDATE TO authenticated USING(
 (private_space_id=(select auth.uid()) AND author_id=(select auth.uid())
  AND status='draft' AND space_id IS NULL AND reply_to IS NULL)
 OR
 (private_space_id IS NULL AND space_id IS NOT NULL AND author_id=(select auth.uid())
  AND status='draft' AND private.is_space_member(space_id)
  AND (SELECT count(*) FROM public.space_members sm WHERE sm.space_id=couple_letters.space_id)=2)
 ) WITH CHECK(
 (private_space_id=(select auth.uid()) AND author_id=(select auth.uid())
  AND status='draft' AND space_id IS NULL AND reply_to IS NULL)
 OR
 (private_space_id IS NULL AND space_id IS NOT NULL AND author_id=(select auth.uid())
  AND private.is_space_member(space_id)
  AND (SELECT count(*) FROM public.space_members sm WHERE sm.space_id=couple_letters.space_id)=2)
 );
DROP POLICY IF EXISTS "QA letter private or paired draft removal only" ON public.couple_letters;
CREATE POLICY "QA letter private or paired draft removal only" ON public.couple_letters
 AS RESTRICTIVE FOR DELETE TO authenticated USING(
 (private_space_id=(select auth.uid()) AND author_id=(select auth.uid())
  AND status='draft' AND space_id IS NULL AND reply_to IS NULL)
 OR
 (private_space_id IS NULL AND space_id IS NOT NULL AND author_id=(select auth.uid())
  AND status='draft' AND private.is_space_member(space_id)
  AND (SELECT count(*) FROM public.space_members sm WHERE sm.space_id=couple_letters.space_id)=2)
 );

CREATE OR REPLACE FUNCTION private.qa_letter_scope_guard()
RETURNS trigger LANGUAGE plpgsql SET search_path='' AS $q$
BEGIN
 IF current_user NOT IN ('authenticated','anon') THEN RETURN NEW; END IF;
 IF tg_op='UPDATE' AND (old.space_id IS DISTINCT FROM new.space_id
  OR old.private_space_id IS DISTINCT FROM new.private_space_id
  OR old.author_id IS DISTINCT FROM new.author_id) THEN
   RAISE EXCEPTION 'Letter storage ownership cannot change in place'
    USING ERRCODE='42501';
 END IF;
 IF new.private_space_id IS NOT NULL AND
   (new.private_space_id IS DISTINCT FROM auth.uid()
    OR new.author_id IS DISTINCT FROM auth.uid()
    OR new.space_id IS NOT NULL
    OR new.status<>'draft' OR new.reply_to IS NOT NULL) THEN
   RAISE EXCEPTION 'Account-owned letters must remain private unsent drafts'
     USING ERRCODE='42501';
 END IF;
 IF new.private_space_id IS NULL AND
   (new.space_id IS NULL OR NOT private.is_space_member(new.space_id)
     OR (SELECT count(*) FROM public.space_members sm WHERE sm.space_id=new.space_id)<>2)
   THEN
     RAISE EXCEPTION 'Shared letters require a current couple'
       USING ERRCODE='42501';
 END IF;
 IF new.private_space_id IS NULL AND new.status='sent' AND
   new.author_id IS DISTINCT FROM auth.uid() AND tg_op='INSERT' THEN
   RAISE EXCEPTION 'Only the signed-in author can send a letter'
    USING ERRCODE='42501';
 END IF;
 RETURN NEW;
END $q$;
REVOKE ALL ON FUNCTION private.qa_letter_scope_guard() FROM public,anon,authenticated;
DROP TRIGGER IF EXISTS zzz_qa_letter_scope_guard ON public.couple_letters;
CREATE TRIGGER zzz_qa_letter_scope_guard BEFORE INSERT OR UPDATE
 ON public.couple_letters FOR EACH ROW EXECUTE FUNCTION private.qa_letter_scope_guard();

-- Read receipts can be associated only with delivered current-pair letters.
ALTER TABLE public.couple_letter_reads ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "QA letter receipts are paired only" ON public.couple_letter_reads;
CREATE POLICY "QA letter receipts are paired only" ON public.couple_letter_reads
 AS RESTRICTIVE FOR SELECT TO authenticated USING(
 EXISTS(SELECT 1 FROM public.couple_letters letter WHERE letter.id=couple_letter_reads.letter_id
  AND letter.private_space_id IS NULL AND letter.space_id IS NOT NULL
  AND letter.status='sent' AND private.is_space_member(letter.space_id)
  AND (SELECT count(*) FROM public.space_members sm WHERE sm.space_id=letter.space_id)=2));
DROP POLICY IF EXISTS "QA letter receipt insert only for paired sent letter" ON public.couple_letter_reads;
CREATE POLICY "QA letter receipt insert only for paired sent letter" ON public.couple_letter_reads
 AS RESTRICTIVE FOR INSERT TO authenticated WITH CHECK(
 reader_id=(select auth.uid()) AND EXISTS(
  SELECT 1 FROM public.couple_letters letter WHERE letter.id=couple_letter_reads.letter_id
    AND letter.private_space_id IS NULL AND letter.space_id IS NOT NULL
    AND letter.status='sent' AND letter.author_id<>reader_id
    AND private.is_space_member(letter.space_id)
    AND (SELECT count(*) FROM public.space_members sm WHERE sm.space_id=letter.space_id)=2));

GRANT SELECT,INSERT,UPDATE,DELETE ON public.couple_letters TO authenticated;
GRANT SELECT,INSERT ON public.couple_letter_reads TO authenticated;
