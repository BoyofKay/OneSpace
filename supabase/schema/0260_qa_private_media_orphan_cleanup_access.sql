-- QA-only: owner may SELECT *their own* unattached private uploads so that
-- Supabase Storage can remove an orphan if the metadata INSERT fails.
-- An attached file still requires its normal parent+metadata read policy.
-- Neither partner nor outsider sees personal files.

DROP POLICY IF EXISTS "QA own unattached cleanup note_images" ON storage.objects;
CREATE POLICY "QA own unattached cleanup note_images" ON storage.objects
 FOR SELECT TO authenticated
 USING(bucket_id='onespace-private-note-images'
   AND (storage.foldername(name))[2]=(select auth.uid())::text
   AND array_length(storage.foldername(name),1)=2
   AND EXISTS(SELECT 1 FROM public.notes parent
      WHERE parent.id=private.note_id_from_image_path(name)
      AND parent.private_space_id=(select auth.uid())
      AND parent.created_by=(select auth.uid())
      AND parent.space_id IS NULL AND parent.visibility='private')
   AND NOT EXISTS(SELECT 1 FROM public.note_images child
      WHERE child.object_path=storage.objects.name
        AND child.storage_bucket_id='onespace-private-note-images'));

DROP POLICY IF EXISTS "QA own unattached cleanup memory_photos" ON storage.objects;
CREATE POLICY "QA own unattached cleanup memory_photos" ON storage.objects
 FOR SELECT TO authenticated
 USING(bucket_id='onespace-private-memory-photos'
   AND (storage.foldername(name))[2]=(select auth.uid())::text
   AND array_length(storage.foldername(name),1)=2
   AND EXISTS(SELECT 1 FROM public.memories parent
      WHERE parent.id=private.memory_id_from_object_path(name)
      AND parent.private_space_id=(select auth.uid())
      AND parent.created_by=(select auth.uid())
      AND parent.space_id IS NULL AND parent.visibility='private')
   AND NOT EXISTS(SELECT 1 FROM public.memory_photos child
      WHERE child.object_path=storage.objects.name
        AND child.storage_bucket_id='onespace-private-memory-photos'));

DROP POLICY IF EXISTS "QA own unattached cleanup trip_attachments" ON storage.objects;
CREATE POLICY "QA own unattached cleanup trip_attachments" ON storage.objects
 FOR SELECT TO authenticated
 USING(bucket_id='onespace-private-trip-documents'
   AND (storage.foldername(name))[2]=(select auth.uid())::text
   AND array_length(storage.foldername(name),1)=2
   AND EXISTS(SELECT 1 FROM public.shared_trips parent
      WHERE parent.id=private.trip_id_from_storage_path(name)
      AND parent.private_space_id=(select auth.uid())
      AND parent.created_by=(select auth.uid())
      AND parent.space_id IS NULL AND parent.visibility='private')
   AND NOT EXISTS(SELECT 1 FROM public.trip_attachments child
      WHERE child.object_path=storage.objects.name
        AND child.storage_bucket_id='onespace-private-trip-documents'));
