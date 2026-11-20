-- QA: legacy permissive read grants must not expose shared inbox files or
-- metadata after a partner departs / stale client references a former space.
ALTER TABLE public.items_to_sort ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "QA read only account owner or current pair inbox" ON public.items_to_sort;
CREATE POLICY "QA read only account owner or current pair inbox"
 ON public.items_to_sort AS RESTRICTIVE FOR SELECT TO authenticated
 USING(
  (private_space_id=(select auth.uid()) AND created_by=(select auth.uid())
     AND space_id IS NULL AND visibility='private')
  OR (private_space_id IS NULL AND space_id IS NOT NULL
     AND visibility='shared' AND private.is_space_member(space_id)
     AND (SELECT count(*) FROM public.space_members m
       WHERE m.space_id=items_to_sort.space_id)=2)
 );
-- Protect against owner-only permissive legacy Storage delete allowing old
-- shared files to be removed from any unrelated couple or via a stale client.
DROP POLICY IF EXISTS "QA shared inbox object removal requires current pair and orphan" ON storage.objects;
CREATE POLICY "QA shared inbox object removal requires current pair and orphan"
 ON storage.objects AS RESTRICTIVE FOR DELETE TO authenticated
 USING(bucket_id<>'onespace-share-in' OR (
  (storage.foldername(name))[1]=(select auth.uid())::text
  AND NOT EXISTS(SELECT 1 FROM public.items_to_sort i
    WHERE i.file_bucket_id='onespace-share-in' AND i.file_path=storage.objects.name)
  AND EXISTS(SELECT 1 FROM public.space_members m WHERE m.user_id=(select auth.uid())
    AND (SELECT count(*) FROM public.space_members x WHERE x.space_id=m.space_id)=2)
 ));
