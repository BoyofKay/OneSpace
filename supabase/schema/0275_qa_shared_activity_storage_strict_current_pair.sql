-- QA: old shared Activity buckets must never accept an account-private
-- Activity root or remain available to an ex-partner after unpairing.
-- RESTRICTIVE policies intersect legacy permissive uploader/reader grants.
DROP POLICY IF EXISTS "QA shared Activity media needs actual current couple" ON storage.objects;
CREATE POLICY "QA shared Activity media needs actual current couple"
 ON storage.objects AS RESTRICTIVE FOR INSERT TO authenticated
 WITH CHECK(bucket_id NOT IN('onespace-activity-media','onespace-activity-voice')
 OR (
  array_length(storage.foldername(name),1)=2
  AND (storage.foldername(name))[2]=(select auth.uid())::text
  AND EXISTS(SELECT 1 FROM public.activities a
   WHERE a.id::text=(storage.foldername(name))[1]
     AND a.private_space_id IS NULL
     AND a.space_id IS NOT NULL
     AND a.visibility='shared' AND private.is_space_member(a.space_id)
     AND (SELECT count(*) FROM public.space_members m
       WHERE m.space_id=a.space_id)=2)
 ));
DROP POLICY IF EXISTS "QA only current pair reads Activity shared media" ON storage.objects;
CREATE POLICY "QA only current pair reads Activity shared media"
 ON storage.objects AS RESTRICTIVE FOR SELECT TO authenticated
 USING(bucket_id NOT IN('onespace-activity-media','onespace-activity-voice')
 OR (
  array_length(storage.foldername(name),1)=2
  AND EXISTS(SELECT 1 FROM public.activities a
   WHERE a.id::text=(storage.foldername(name))[1]
     AND a.private_space_id IS NULL AND a.space_id IS NOT NULL
     AND a.visibility='shared' AND private.is_space_member(a.space_id)
     AND (SELECT count(*) FROM public.space_members m
      WHERE m.space_id=a.space_id)=2)
 ));
DROP POLICY IF EXISTS "QA shared Activity cleanup requires still-current couple" ON storage.objects;
CREATE POLICY "QA shared Activity cleanup requires still-current couple"
 ON storage.objects AS RESTRICTIVE FOR DELETE TO authenticated
 USING(bucket_id NOT IN('onespace-activity-media','onespace-activity-voice')
 OR EXISTS(SELECT 1 FROM public.activities a
  WHERE a.id::text=(storage.foldername(name))[1]
  AND a.space_id IS NOT NULL AND a.private_space_id IS NULL AND a.visibility='shared'
  AND private.is_space_member(a.space_id)
  AND (SELECT count(*) FROM public.space_members m WHERE m.space_id=a.space_id)=2));
