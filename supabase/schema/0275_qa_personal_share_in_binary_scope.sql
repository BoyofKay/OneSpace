-- Reconciled 2026-11-20: applied to QA (ugwrpeduzyzrujkizqfo) on 2026-11-20 from
-- qa/activities-memories-two-scope-cutover-20261120:supabase/schema/0268_qa_personal_share_in_binary_scope.sql (original number 0268). Kept verbatim so the
-- repository replays to the live QA schema. QA only; never apply to Production.
-- QA ONLY: account-owned incoming image/PDF files, separate from the couple
-- bucket. Keep old couple file paths intact; never relocate them to a new partner.
INSERT INTO storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
VALUES('onespace-private-share-in','onespace-private-share-in',false,10485760,
 ARRAY['image/jpeg','image/png','image/webp','image/heic','application/pdf']::text[])
ON CONFLICT(id) DO NOTHING;

ALTER TABLE public.items_to_sort
 ADD COLUMN IF NOT EXISTS file_bucket_id text NOT NULL DEFAULT 'onespace-share-in';
ALTER TABLE public.items_to_sort DROP CONSTRAINT IF EXISTS qa_sort_file_bucket_consistency;
ALTER TABLE public.items_to_sort ADD CONSTRAINT qa_sort_file_bucket_consistency CHECK(
 file_bucket_id IN('onespace-share-in','onespace-private-share-in')
 AND (file_path IS NULL OR
 (private_space_id IS NOT NULL AND space_id IS NULL
     AND visibility='private' AND file_bucket_id='onespace-private-share-in')
 OR (private_space_id IS NULL AND space_id IS NOT NULL
     AND visibility='shared' AND file_bucket_id='onespace-share-in'))
 ) NOT VALID;
-- Existing account-private text rows can retain their default bucket value.
CREATE OR REPLACE FUNCTION private.qa_sort_inbox_scope_guard()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $q$
BEGIN
 IF current_user IN ('authenticated','anon') THEN
  IF tg_op='UPDATE' AND (
    old.space_id IS DISTINCT FROM new.space_id
    OR old.private_space_id IS DISTINCT FROM new.private_space_id
    OR old.created_by IS DISTINCT FROM new.created_by
    OR old.visibility IS DISTINCT FROM new.visibility
    OR old.file_path IS DISTINCT FROM new.file_path
    OR old.file_name IS DISTINCT FROM new.file_name
    OR old.file_mime IS DISTINCT FROM new.file_mime
    OR old.file_size IS DISTINCT FROM new.file_size
    OR old.file_bucket_id IS DISTINCT FROM new.file_bucket_id) THEN
     RAISE EXCEPTION 'Inbox ownership, privacy and attachment are immutable'
       USING ERRCODE='42501';
  END IF;
  IF new.private_space_id IS NOT NULL THEN
    IF new.private_space_id IS DISTINCT FROM auth.uid()
      OR new.created_by IS DISTINCT FROM auth.uid()
      OR new.space_id IS NOT NULL OR new.visibility<>'private'
      OR (new.file_path IS NOT NULL
        AND (new.file_bucket_id<>'onespace-private-share-in'
         OR split_part(new.file_path,'/',1)<>auth.uid()::text
         OR new.file_path !~ ('^'||auth.uid()::text||
             '/[0-9a-f-]{36}[.](jpg|jpeg|png|webp|heic|pdf)$'))) THEN
      RAISE EXCEPTION 'Personal inbox file must stay in its author-owned bucket'
        USING ERRCODE='42501';
    END IF;
  ELSIF new.space_id IS NOT NULL THEN
    IF new.visibility='private' OR
      (new.file_path IS NOT NULL AND
        (new.file_bucket_id<>'onespace-share-in' OR
         split_part(new.file_path,'/',1)<>new.created_by::text))
    THEN RAISE EXCEPTION 'Couple inbox attachment is not a private account item'
      USING ERRCODE='42501';
    END IF;
  END IF;
 END IF;
 RETURN new;
END $q$;
REVOKE ALL ON FUNCTION private.qa_sort_inbox_scope_guard() FROM PUBLIC,anon,authenticated;

-- Old text-only private insert/update policy stays: add a separate explicit
-- private file insert and update route under restrictive same-scope validation.
DROP POLICY IF EXISTS "QA owner inserts private inbox file" ON public.items_to_sort;
CREATE POLICY "QA owner inserts private inbox file"
 ON public.items_to_sort FOR INSERT TO authenticated
 WITH CHECK(
  private_space_id=(select auth.uid()) AND created_by=(select auth.uid())
  AND space_id IS NULL AND visibility='private'
  AND file_path IS NOT NULL AND file_bucket_id='onespace-private-share-in'
  AND file_mime IN('image/jpeg','image/png','image/webp','image/heic','application/pdf')
  AND file_size BETWEEN 1 AND 10485760
  AND split_part(file_path,'/',1)=(select auth.uid())::text
 );
DROP POLICY IF EXISTS "QA valid private inbox file and pair INSERT" ON public.items_to_sort;
CREATE POLICY "QA valid private inbox file and pair INSERT"
 ON public.items_to_sort AS RESTRICTIVE FOR INSERT TO authenticated
 WITH CHECK(
 (private_space_id=(select auth.uid()) AND created_by=(select auth.uid())
  AND space_id IS NULL AND visibility='private'
  AND (file_path IS NULL OR (
    file_bucket_id='onespace-private-share-in'
    AND split_part(file_path,'/',1)=(select auth.uid())::text)))
 OR (private_space_id IS NULL AND space_id IS NOT NULL
  AND visibility='shared' AND private.is_space_member(space_id)
  AND (select count(*) FROM public.space_members m WHERE m.space_id=items_to_sort.space_id)=2
  AND (file_path IS NULL OR file_bucket_id='onespace-share-in')));
DROP POLICY IF EXISTS "QA valid private inbox file and pair UPDATE" ON public.items_to_sort;
CREATE POLICY "QA valid private inbox file and pair UPDATE"
 ON public.items_to_sort AS RESTRICTIVE FOR UPDATE TO authenticated
 USING(
 (private_space_id=(select auth.uid()) AND created_by=(select auth.uid())
   AND space_id IS NULL AND visibility='private')
 OR (private_space_id IS NULL AND space_id IS NOT NULL AND visibility='shared'
   AND private.is_space_member(space_id)
   AND (select count(*) FROM public.space_members m WHERE m.space_id=items_to_sort.space_id)=2))
 WITH CHECK(
 (private_space_id=(select auth.uid()) AND created_by=(select auth.uid())
  AND space_id IS NULL AND visibility='private'
  AND (file_path IS NULL OR file_bucket_id='onespace-private-share-in'))
 OR (private_space_id IS NULL AND space_id IS NOT NULL AND visibility='shared'
   AND private.is_space_member(space_id)
   AND (select count(*) FROM public.space_members m WHERE m.space_id=items_to_sort.space_id)=2
   AND (file_path IS NULL OR file_bucket_id='onespace-share-in')));

-- Unconditionally restrict old permissive shared Storage read to an actual
-- visible couple inbox entry, never merely a matching user folder.
DROP POLICY IF EXISTS "QA Share-in reads only currently paired shared files" ON storage.objects;
CREATE POLICY "QA Share-in reads only currently paired shared files"
 ON storage.objects AS RESTRICTIVE FOR SELECT TO authenticated
 USING(bucket_id<>'onespace-share-in' OR EXISTS(
  SELECT 1 FROM public.items_to_sort i WHERE i.file_path=storage.objects.name
    AND i.file_bucket_id='onespace-share-in'
    AND i.space_id IS NOT NULL AND i.private_space_id IS NULL AND i.visibility='shared'
    AND private.is_space_member(i.space_id)
    AND (SELECT count(*) FROM public.space_members m WHERE m.space_id=i.space_id)=2));
-- Share-in insertion into the new bucket checks the user's account namespace.
DROP POLICY IF EXISTS "QA Upload personal share-in attachment" ON storage.objects;
CREATE POLICY "QA Upload personal share-in attachment"
 ON storage.objects FOR INSERT TO authenticated
 WITH CHECK(bucket_id='onespace-private-share-in'
  AND (storage.foldername(name))[1]=(select auth.uid())::text
  AND array_length(storage.foldername(name),1)=1
  AND EXISTS(SELECT 1 FROM public.user_private_spaces p
     WHERE p.owner_id=(select auth.uid())));

DROP POLICY IF EXISTS "QA Read owner personal Share-in bytes" ON storage.objects;
CREATE POLICY "QA Read owner personal Share-in bytes"
 ON storage.objects FOR SELECT TO authenticated USING(
 bucket_id='onespace-private-share-in'
 AND (storage.foldername(name))[1]=(select auth.uid())::text
 AND (
   EXISTS(SELECT 1 FROM public.items_to_sort i WHERE i.file_path=storage.objects.name
    AND i.file_bucket_id='onespace-private-share-in'
    AND i.private_space_id=(select auth.uid())
    AND i.created_by=(select auth.uid()) AND i.space_id IS NULL
    AND i.visibility='private')
   OR (storage.objects.created_at>now()-interval '10 minutes' AND
      NOT EXISTS(SELECT 1 FROM public.items_to_sort i
       WHERE i.file_path=storage.objects.name AND i.file_bucket_id='onespace-private-share-in'))
 ));

DROP POLICY IF EXISTS "QA Delete unused personal Share-in bytes" ON storage.objects;
CREATE POLICY "QA Delete unused personal Share-in bytes"
 ON storage.objects FOR DELETE TO authenticated USING(
 bucket_id='onespace-private-share-in'
 AND (storage.foldername(name))[1]=(select auth.uid())::text
 AND NOT EXISTS(SELECT 1 FROM public.items_to_sort i
   WHERE i.file_path=storage.objects.name AND i.file_bucket_id='onespace-private-share-in'));
