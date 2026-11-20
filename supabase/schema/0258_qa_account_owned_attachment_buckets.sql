-- QA ONLY: separate private Storage buckets for Notes, Memories and Trips.
-- Existing objects remain in original couple-owned buckets; no objects copied or deleted.
-- The attachment metadata explicitly identifies the bucket and cannot switch in-place.
-- The old Storage buckets remain accessible only through their existing policies.

INSERT INTO storage.buckets (id,name,public,file_size_limit,allowed_mime_types)
VALUES('onespace-private-note-images','onespace-private-note-images',false,10485760,ARRAY['image/jpeg','image/png','image/webp']::text[])
ON CONFLICT(id) DO NOTHING;
ALTER TABLE public.note_images ADD COLUMN IF NOT EXISTS storage_bucket_id text
 NOT NULL DEFAULT 'onespace-note-images';
DO $q$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='public.note_images'::regclass AND conname='qa_note_images_storage_bucket_check') THEN
 ALTER TABLE public.note_images ADD CONSTRAINT qa_note_images_storage_bucket_check
 CHECK(storage_bucket_id IN ('onespace-note-images','onespace-private-note-images')) NOT VALID;
 END IF;
END $q$;
ALTER TABLE public.note_images ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "QA note_images bucket and parent SELECT" ON public.note_images;
CREATE POLICY "QA note_images bucket and parent SELECT" ON public.note_images
 AS RESTRICTIVE FOR SELECT TO authenticated USING(
 EXISTS(SELECT 1 FROM public.notes p WHERE p.id=note_images.note_id
  AND ((p.private_space_id=(select auth.uid()) AND p.created_by=(select auth.uid())
    AND p.visibility='private' AND p.space_id IS NULL
    AND note_images.created_by=(select auth.uid())
    AND note_images.storage_bucket_id='onespace-private-note-images')
   OR (p.private_space_id IS NULL AND p.visibility='shared'
    AND p.space_id IS NOT NULL AND private.is_space_member(p.space_id)
    AND (SELECT count(*) FROM public.space_members m WHERE m.space_id=p.space_id)=2
    AND note_images.storage_bucket_id='onespace-note-images'))));
DROP POLICY IF EXISTS "QA note_images personal insert" ON public.note_images;
CREATE POLICY "QA note_images personal insert" ON public.note_images
 FOR INSERT TO authenticated WITH CHECK(created_by=(select auth.uid())
 AND storage_bucket_id='onespace-private-note-images' AND EXISTS(
  SELECT 1 FROM public.notes p WHERE p.id=note_images.note_id
   AND p.private_space_id=(select auth.uid()) AND p.created_by=(select auth.uid())
   AND p.space_id IS NULL AND p.visibility='private'));
DROP POLICY IF EXISTS "QA note_images bucket and parent INSERT" ON public.note_images;
CREATE POLICY "QA note_images bucket and parent INSERT" ON public.note_images
 AS RESTRICTIVE FOR INSERT TO authenticated WITH CHECK(
 created_by=(select auth.uid()) AND EXISTS(
  SELECT 1 FROM public.notes p WHERE p.id=note_images.note_id
  AND ((p.private_space_id=(select auth.uid()) AND p.created_by=(select auth.uid())
    AND p.space_id IS NULL AND p.visibility='private'
    AND note_images.storage_bucket_id='onespace-private-note-images')
   OR (p.private_space_id IS NULL AND p.visibility='shared'
    AND p.space_id IS NOT NULL AND private.is_space_member(p.space_id)
    AND (SELECT count(*) FROM public.space_members m WHERE m.space_id=p.space_id)=2
    AND note_images.storage_bucket_id='onespace-note-images'))));
DROP POLICY IF EXISTS "QA note_images personal update" ON public.note_images;
CREATE POLICY "QA note_images personal update" ON public.note_images
 FOR UPDATE TO authenticated
 USING(created_by=(select auth.uid()) AND storage_bucket_id='onespace-private-note-images'
 AND EXISTS(SELECT 1 FROM public.notes p WHERE p.id=note_images.note_id
    AND p.private_space_id=(select auth.uid()) AND p.created_by=(select auth.uid())
    AND p.space_id IS NULL AND p.visibility='private'))
 WITH CHECK(created_by=(select auth.uid()) AND storage_bucket_id='onespace-private-note-images'
 AND EXISTS(SELECT 1 FROM public.notes p WHERE p.id=note_images.note_id
    AND p.private_space_id=(select auth.uid()) AND p.created_by=(select auth.uid())
    AND p.space_id IS NULL AND p.visibility='private'));
DROP POLICY IF EXISTS "QA note_images bucket and parent UPDATE" ON public.note_images;
CREATE POLICY "QA note_images bucket and parent UPDATE" ON public.note_images
 AS RESTRICTIVE FOR UPDATE TO authenticated
 USING(EXISTS(SELECT 1 FROM public.notes p WHERE p.id=note_images.note_id
 AND ((p.private_space_id=(select auth.uid()) AND p.created_by=(select auth.uid())
  AND p.space_id IS NULL AND p.visibility='private' AND created_by=(select auth.uid())
  AND storage_bucket_id='onespace-private-note-images')
 OR(p.private_space_id IS NULL AND p.visibility='shared' AND private.is_space_member(p.space_id)
  AND (SELECT count(*) FROM public.space_members m WHERE m.space_id=p.space_id)=2
  AND storage_bucket_id='onespace-note-images'))))
 WITH CHECK(EXISTS(SELECT 1 FROM public.notes p WHERE p.id=note_images.note_id
 AND ((p.private_space_id=(select auth.uid()) AND p.created_by=(select auth.uid())
  AND p.space_id IS NULL AND p.visibility='private' AND created_by=(select auth.uid())
  AND storage_bucket_id='onespace-private-note-images')
 OR(p.private_space_id IS NULL AND p.visibility='shared' AND private.is_space_member(p.space_id)
  AND (SELECT count(*) FROM public.space_members m WHERE m.space_id=p.space_id)=2
  AND storage_bucket_id='onespace-note-images'))));

INSERT INTO storage.buckets (id,name,public,file_size_limit,allowed_mime_types)
VALUES('onespace-private-memory-photos','onespace-private-memory-photos',false,6291456,ARRAY['image/jpeg','image/png','image/webp']::text[])
ON CONFLICT(id) DO NOTHING;
ALTER TABLE public.memory_photos ADD COLUMN IF NOT EXISTS storage_bucket_id text
 NOT NULL DEFAULT 'onespace-memory-photos';
DO $q$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='public.memory_photos'::regclass AND conname='qa_memory_photos_storage_bucket_check') THEN
 ALTER TABLE public.memory_photos ADD CONSTRAINT qa_memory_photos_storage_bucket_check
 CHECK(storage_bucket_id IN ('onespace-memory-photos','onespace-private-memory-photos')) NOT VALID;
 END IF;
END $q$;
ALTER TABLE public.memory_photos ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "QA memory_photos bucket and parent SELECT" ON public.memory_photos;
CREATE POLICY "QA memory_photos bucket and parent SELECT" ON public.memory_photos
 AS RESTRICTIVE FOR SELECT TO authenticated USING(
 EXISTS(SELECT 1 FROM public.memories p WHERE p.id=memory_photos.memory_id
  AND ((p.private_space_id=(select auth.uid()) AND p.created_by=(select auth.uid())
    AND p.visibility='private' AND p.space_id IS NULL
    AND memory_photos.created_by=(select auth.uid())
    AND memory_photos.storage_bucket_id='onespace-private-memory-photos')
   OR (p.private_space_id IS NULL AND p.visibility='shared'
    AND p.space_id IS NOT NULL AND private.is_space_member(p.space_id)
    AND (SELECT count(*) FROM public.space_members m WHERE m.space_id=p.space_id)=2
    AND memory_photos.storage_bucket_id='onespace-memory-photos'))));
DROP POLICY IF EXISTS "QA memory_photos personal insert" ON public.memory_photos;
CREATE POLICY "QA memory_photos personal insert" ON public.memory_photos
 FOR INSERT TO authenticated WITH CHECK(created_by=(select auth.uid())
 AND storage_bucket_id='onespace-private-memory-photos' AND EXISTS(
  SELECT 1 FROM public.memories p WHERE p.id=memory_photos.memory_id
   AND p.private_space_id=(select auth.uid()) AND p.created_by=(select auth.uid())
   AND p.space_id IS NULL AND p.visibility='private'));
DROP POLICY IF EXISTS "QA memory_photos bucket and parent INSERT" ON public.memory_photos;
CREATE POLICY "QA memory_photos bucket and parent INSERT" ON public.memory_photos
 AS RESTRICTIVE FOR INSERT TO authenticated WITH CHECK(
 created_by=(select auth.uid()) AND EXISTS(
  SELECT 1 FROM public.memories p WHERE p.id=memory_photos.memory_id
  AND ((p.private_space_id=(select auth.uid()) AND p.created_by=(select auth.uid())
    AND p.space_id IS NULL AND p.visibility='private'
    AND memory_photos.storage_bucket_id='onespace-private-memory-photos')
   OR (p.private_space_id IS NULL AND p.visibility='shared'
    AND p.space_id IS NOT NULL AND private.is_space_member(p.space_id)
    AND (SELECT count(*) FROM public.space_members m WHERE m.space_id=p.space_id)=2
    AND memory_photos.storage_bucket_id='onespace-memory-photos'))));
DROP POLICY IF EXISTS "QA memory_photos personal update" ON public.memory_photos;
CREATE POLICY "QA memory_photos personal update" ON public.memory_photos
 FOR UPDATE TO authenticated
 USING(created_by=(select auth.uid()) AND storage_bucket_id='onespace-private-memory-photos'
 AND EXISTS(SELECT 1 FROM public.memories p WHERE p.id=memory_photos.memory_id
    AND p.private_space_id=(select auth.uid()) AND p.created_by=(select auth.uid())
    AND p.space_id IS NULL AND p.visibility='private'))
 WITH CHECK(created_by=(select auth.uid()) AND storage_bucket_id='onespace-private-memory-photos'
 AND EXISTS(SELECT 1 FROM public.memories p WHERE p.id=memory_photos.memory_id
    AND p.private_space_id=(select auth.uid()) AND p.created_by=(select auth.uid())
    AND p.space_id IS NULL AND p.visibility='private'));
DROP POLICY IF EXISTS "QA memory_photos bucket and parent UPDATE" ON public.memory_photos;
CREATE POLICY "QA memory_photos bucket and parent UPDATE" ON public.memory_photos
 AS RESTRICTIVE FOR UPDATE TO authenticated
 USING(EXISTS(SELECT 1 FROM public.memories p WHERE p.id=memory_photos.memory_id
 AND ((p.private_space_id=(select auth.uid()) AND p.created_by=(select auth.uid())
  AND p.space_id IS NULL AND p.visibility='private' AND created_by=(select auth.uid())
  AND storage_bucket_id='onespace-private-memory-photos')
 OR(p.private_space_id IS NULL AND p.visibility='shared' AND private.is_space_member(p.space_id)
  AND (SELECT count(*) FROM public.space_members m WHERE m.space_id=p.space_id)=2
  AND storage_bucket_id='onespace-memory-photos'))))
 WITH CHECK(EXISTS(SELECT 1 FROM public.memories p WHERE p.id=memory_photos.memory_id
 AND ((p.private_space_id=(select auth.uid()) AND p.created_by=(select auth.uid())
  AND p.space_id IS NULL AND p.visibility='private' AND created_by=(select auth.uid())
  AND storage_bucket_id='onespace-private-memory-photos')
 OR(p.private_space_id IS NULL AND p.visibility='shared' AND private.is_space_member(p.space_id)
  AND (SELECT count(*) FROM public.space_members m WHERE m.space_id=p.space_id)=2
  AND storage_bucket_id='onespace-memory-photos'))));

INSERT INTO storage.buckets (id,name,public,file_size_limit,allowed_mime_types)
VALUES('onespace-private-trip-documents','onespace-private-trip-documents',false,10485760,ARRAY['application/pdf','image/jpeg','image/png','image/webp']::text[])
ON CONFLICT(id) DO NOTHING;
ALTER TABLE public.trip_attachments ADD COLUMN IF NOT EXISTS storage_bucket_id text
 NOT NULL DEFAULT 'onespace-trip-documents';
DO $q$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='public.trip_attachments'::regclass AND conname='qa_trip_attachments_storage_bucket_check') THEN
 ALTER TABLE public.trip_attachments ADD CONSTRAINT qa_trip_attachments_storage_bucket_check
 CHECK(storage_bucket_id IN ('onespace-trip-documents','onespace-private-trip-documents')) NOT VALID;
 END IF;
END $q$;
ALTER TABLE public.trip_attachments ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "QA trip_attachments bucket and parent SELECT" ON public.trip_attachments;
CREATE POLICY "QA trip_attachments bucket and parent SELECT" ON public.trip_attachments
 AS RESTRICTIVE FOR SELECT TO authenticated USING(
 EXISTS(SELECT 1 FROM public.shared_trips p WHERE p.id=trip_attachments.trip_id
  AND ((p.private_space_id=(select auth.uid()) AND p.created_by=(select auth.uid())
    AND p.visibility='private' AND p.space_id IS NULL
    AND trip_attachments.created_by=(select auth.uid())
    AND trip_attachments.storage_bucket_id='onespace-private-trip-documents')
   OR (p.private_space_id IS NULL AND p.visibility='shared'
    AND p.space_id IS NOT NULL AND private.is_space_member(p.space_id)
    AND (SELECT count(*) FROM public.space_members m WHERE m.space_id=p.space_id)=2
    AND trip_attachments.storage_bucket_id='onespace-trip-documents'))));
DROP POLICY IF EXISTS "QA trip_attachments personal insert" ON public.trip_attachments;
CREATE POLICY "QA trip_attachments personal insert" ON public.trip_attachments
 FOR INSERT TO authenticated WITH CHECK(created_by=(select auth.uid())
 AND storage_bucket_id='onespace-private-trip-documents' AND EXISTS(
  SELECT 1 FROM public.shared_trips p WHERE p.id=trip_attachments.trip_id
   AND p.private_space_id=(select auth.uid()) AND p.created_by=(select auth.uid())
   AND p.space_id IS NULL AND p.visibility='private'));
DROP POLICY IF EXISTS "QA trip_attachments bucket and parent INSERT" ON public.trip_attachments;
CREATE POLICY "QA trip_attachments bucket and parent INSERT" ON public.trip_attachments
 AS RESTRICTIVE FOR INSERT TO authenticated WITH CHECK(
 created_by=(select auth.uid()) AND EXISTS(
  SELECT 1 FROM public.shared_trips p WHERE p.id=trip_attachments.trip_id
  AND ((p.private_space_id=(select auth.uid()) AND p.created_by=(select auth.uid())
    AND p.space_id IS NULL AND p.visibility='private'
    AND trip_attachments.storage_bucket_id='onespace-private-trip-documents')
   OR (p.private_space_id IS NULL AND p.visibility='shared'
    AND p.space_id IS NOT NULL AND private.is_space_member(p.space_id)
    AND (SELECT count(*) FROM public.space_members m WHERE m.space_id=p.space_id)=2
    AND trip_attachments.storage_bucket_id='onespace-trip-documents'))));
DROP POLICY IF EXISTS "QA trip_attachments personal update" ON public.trip_attachments;
CREATE POLICY "QA trip_attachments personal update" ON public.trip_attachments
 FOR UPDATE TO authenticated
 USING(created_by=(select auth.uid()) AND storage_bucket_id='onespace-private-trip-documents'
 AND EXISTS(SELECT 1 FROM public.shared_trips p WHERE p.id=trip_attachments.trip_id
    AND p.private_space_id=(select auth.uid()) AND p.created_by=(select auth.uid())
    AND p.space_id IS NULL AND p.visibility='private'))
 WITH CHECK(created_by=(select auth.uid()) AND storage_bucket_id='onespace-private-trip-documents'
 AND EXISTS(SELECT 1 FROM public.shared_trips p WHERE p.id=trip_attachments.trip_id
    AND p.private_space_id=(select auth.uid()) AND p.created_by=(select auth.uid())
    AND p.space_id IS NULL AND p.visibility='private'));
DROP POLICY IF EXISTS "QA trip_attachments bucket and parent UPDATE" ON public.trip_attachments;
CREATE POLICY "QA trip_attachments bucket and parent UPDATE" ON public.trip_attachments
 AS RESTRICTIVE FOR UPDATE TO authenticated
 USING(EXISTS(SELECT 1 FROM public.shared_trips p WHERE p.id=trip_attachments.trip_id
 AND ((p.private_space_id=(select auth.uid()) AND p.created_by=(select auth.uid())
  AND p.space_id IS NULL AND p.visibility='private' AND created_by=(select auth.uid())
  AND storage_bucket_id='onespace-private-trip-documents')
 OR(p.private_space_id IS NULL AND p.visibility='shared' AND private.is_space_member(p.space_id)
  AND (SELECT count(*) FROM public.space_members m WHERE m.space_id=p.space_id)=2
  AND storage_bucket_id='onespace-trip-documents'))))
 WITH CHECK(EXISTS(SELECT 1 FROM public.shared_trips p WHERE p.id=trip_attachments.trip_id
 AND ((p.private_space_id=(select auth.uid()) AND p.created_by=(select auth.uid())
  AND p.space_id IS NULL AND p.visibility='private' AND created_by=(select auth.uid())
  AND storage_bucket_id='onespace-private-trip-documents')
 OR(p.private_space_id IS NULL AND p.visibility='shared' AND private.is_space_member(p.space_id)
  AND (SELECT count(*) FROM public.space_members m WHERE m.space_id=p.space_id)=2
  AND storage_bucket_id='onespace-trip-documents'))));

CREATE OR REPLACE FUNCTION private.qa_attachment_scope_immutable()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $q$
BEGIN
 IF current_user NOT IN ('authenticated','anon') THEN RETURN new;END IF;
 IF tg_op='UPDATE' AND (
 old.storage_bucket_id IS DISTINCT FROM new.storage_bucket_id OR
 old.object_path IS DISTINCT FROM new.object_path OR
 old.created_by IS DISTINCT FROM new.created_by OR
 old.id IS DISTINCT FROM new.id) THEN
   RAISE EXCEPTION 'Attachment ownership and storage path are immutable' USING ERRCODE='42501';
 END IF;
 IF tg_op='UPDATE' THEN
 IF tg_table_name='note_images' AND old.note_id IS DISTINCT FROM new.note_id THEN
   RAISE EXCEPTION 'Note image parent cannot change' USING ERRCODE='42501';
 ELSIF tg_table_name='memory_photos' AND old.memory_id IS DISTINCT FROM new.memory_id THEN
   RAISE EXCEPTION 'Memory photo parent cannot change' USING ERRCODE='42501';
 ELSIF tg_table_name='trip_attachments' AND old.trip_id IS DISTINCT FROM new.trip_id THEN
   RAISE EXCEPTION 'Travel attachment parent cannot change' USING ERRCODE='42501';
 END IF;
 END IF;
 RETURN new;
END $q$;
REVOKE ALL ON FUNCTION private.qa_attachment_scope_immutable() FROM PUBLIC,anon,authenticated;

DROP TRIGGER IF EXISTS zzz_qa_attachment_scope_immutable ON public.note_images;
CREATE TRIGGER zzz_qa_attachment_scope_immutable
 BEFORE INSERT OR UPDATE ON public.note_images FOR EACH ROW
 EXECUTE FUNCTION private.qa_attachment_scope_immutable();
GRANT SELECT,INSERT,UPDATE ON public.note_images TO authenticated;

-- A private object path preserves the existing root/author/UUID format,
-- but is stored in a completely different private bucket, never the couple bucket.
DROP POLICY IF EXISTS "QA account uploads note_images" ON storage.objects;
CREATE POLICY "QA account uploads note_images" ON storage.objects
 FOR INSERT TO authenticated WITH CHECK(bucket_id='onespace-private-note-images'
 AND (storage.foldername(name))[2]=(select auth.uid())::text
 AND array_length(storage.foldername(name),1)=2
 AND EXISTS(SELECT 1 FROM public.notes p WHERE p.id=private.note_id_from_image_path(name)
  AND p.private_space_id=(select auth.uid()) AND p.created_by=(select auth.uid())
  AND p.space_id IS NULL AND p.visibility='private'));
DROP POLICY IF EXISTS "QA account views note_images" ON storage.objects;
CREATE POLICY "QA account views note_images" ON storage.objects
 FOR SELECT TO authenticated USING(bucket_id='onespace-private-note-images'
 AND EXISTS(SELECT 1 FROM public.note_images a
 JOIN public.notes p ON p.id=a.note_id
 WHERE a.object_path=storage.objects.name AND a.storage_bucket_id='onespace-private-note-images'
  AND a.archived_at IS NULL
  AND p.private_space_id=(select auth.uid()) AND p.created_by=(select auth.uid())
  AND a.created_by=(select auth.uid()) AND p.space_id IS NULL
  AND p.visibility='private' AND p.archived_at IS NULL));
DROP POLICY IF EXISTS "QA remove unused personal note_images" ON storage.objects;
CREATE POLICY "QA remove unused personal note_images" ON storage.objects
 FOR DELETE TO authenticated USING(bucket_id='onespace-private-note-images'
 AND (storage.foldername(name))[2]=(select auth.uid())::text
 AND EXISTS(SELECT 1 FROM public.notes p WHERE p.id=private.note_id_from_image_path(name)
  AND p.private_space_id=(select auth.uid()) AND p.created_by=(select auth.uid())
  AND p.space_id IS NULL AND p.visibility='private')
 AND NOT EXISTS(SELECT 1 FROM public.note_images a
  WHERE a.object_path=storage.objects.name AND a.storage_bucket_id='onespace-private-note-images'));

DROP TRIGGER IF EXISTS zzz_qa_attachment_scope_immutable ON public.memory_photos;
CREATE TRIGGER zzz_qa_attachment_scope_immutable
 BEFORE INSERT OR UPDATE ON public.memory_photos FOR EACH ROW
 EXECUTE FUNCTION private.qa_attachment_scope_immutable();
GRANT SELECT,INSERT,UPDATE ON public.memory_photos TO authenticated;

-- A private object path preserves the existing root/author/UUID format,
-- but is stored in a completely different private bucket, never the couple bucket.
DROP POLICY IF EXISTS "QA account uploads memory_photos" ON storage.objects;
CREATE POLICY "QA account uploads memory_photos" ON storage.objects
 FOR INSERT TO authenticated WITH CHECK(bucket_id='onespace-private-memory-photos'
 AND (storage.foldername(name))[2]=(select auth.uid())::text
 AND array_length(storage.foldername(name),1)=2
 AND EXISTS(SELECT 1 FROM public.memories p WHERE p.id=private.memory_id_from_object_path(name)
  AND p.private_space_id=(select auth.uid()) AND p.created_by=(select auth.uid())
  AND p.space_id IS NULL AND p.visibility='private'));
DROP POLICY IF EXISTS "QA account views memory_photos" ON storage.objects;
CREATE POLICY "QA account views memory_photos" ON storage.objects
 FOR SELECT TO authenticated USING(bucket_id='onespace-private-memory-photos'
 AND EXISTS(SELECT 1 FROM public.memory_photos a
 JOIN public.memories p ON p.id=a.memory_id
 WHERE a.object_path=storage.objects.name AND a.storage_bucket_id='onespace-private-memory-photos'
  AND a.archived_at IS NULL
  AND p.private_space_id=(select auth.uid()) AND p.created_by=(select auth.uid())
  AND a.created_by=(select auth.uid()) AND p.space_id IS NULL
  AND p.visibility='private' AND p.archived_at IS NULL));
DROP POLICY IF EXISTS "QA remove unused personal memory_photos" ON storage.objects;
CREATE POLICY "QA remove unused personal memory_photos" ON storage.objects
 FOR DELETE TO authenticated USING(bucket_id='onespace-private-memory-photos'
 AND (storage.foldername(name))[2]=(select auth.uid())::text
 AND EXISTS(SELECT 1 FROM public.memories p WHERE p.id=private.memory_id_from_object_path(name)
  AND p.private_space_id=(select auth.uid()) AND p.created_by=(select auth.uid())
  AND p.space_id IS NULL AND p.visibility='private')
 AND NOT EXISTS(SELECT 1 FROM public.memory_photos a
  WHERE a.object_path=storage.objects.name AND a.storage_bucket_id='onespace-private-memory-photos'));

DROP TRIGGER IF EXISTS zzz_qa_attachment_scope_immutable ON public.trip_attachments;
CREATE TRIGGER zzz_qa_attachment_scope_immutable
 BEFORE INSERT OR UPDATE ON public.trip_attachments FOR EACH ROW
 EXECUTE FUNCTION private.qa_attachment_scope_immutable();
GRANT SELECT,INSERT,UPDATE ON public.trip_attachments TO authenticated;

-- A private object path preserves the existing root/author/UUID format,
-- but is stored in a completely different private bucket, never the couple bucket.
DROP POLICY IF EXISTS "QA account uploads trip_attachments" ON storage.objects;
CREATE POLICY "QA account uploads trip_attachments" ON storage.objects
 FOR INSERT TO authenticated WITH CHECK(bucket_id='onespace-private-trip-documents'
 AND (storage.foldername(name))[2]=(select auth.uid())::text
 AND array_length(storage.foldername(name),1)=2
 AND EXISTS(SELECT 1 FROM public.shared_trips p WHERE p.id=private.trip_id_from_storage_path(name)
  AND p.private_space_id=(select auth.uid()) AND p.created_by=(select auth.uid())
  AND p.space_id IS NULL AND p.visibility='private'));
DROP POLICY IF EXISTS "QA account views trip_attachments" ON storage.objects;
CREATE POLICY "QA account views trip_attachments" ON storage.objects
 FOR SELECT TO authenticated USING(bucket_id='onespace-private-trip-documents'
 AND EXISTS(SELECT 1 FROM public.trip_attachments a
 JOIN public.shared_trips p ON p.id=a.trip_id
 WHERE a.object_path=storage.objects.name AND a.storage_bucket_id='onespace-private-trip-documents'
  AND a.archived_at IS NULL
  AND p.private_space_id=(select auth.uid()) AND p.created_by=(select auth.uid())
  AND a.created_by=(select auth.uid()) AND p.space_id IS NULL
  AND p.visibility='private' AND p.archived_at IS NULL));
DROP POLICY IF EXISTS "QA remove unused personal trip_attachments" ON storage.objects;
CREATE POLICY "QA remove unused personal trip_attachments" ON storage.objects
 FOR DELETE TO authenticated USING(bucket_id='onespace-private-trip-documents'
 AND (storage.foldername(name))[2]=(select auth.uid())::text
 AND EXISTS(SELECT 1 FROM public.shared_trips p WHERE p.id=private.trip_id_from_storage_path(name)
  AND p.private_space_id=(select auth.uid()) AND p.created_by=(select auth.uid())
  AND p.space_id IS NULL AND p.visibility='private')
 AND NOT EXISTS(SELECT 1 FROM public.trip_attachments a
  WHERE a.object_path=storage.objects.name AND a.storage_bucket_id='onespace-private-trip-documents'));
