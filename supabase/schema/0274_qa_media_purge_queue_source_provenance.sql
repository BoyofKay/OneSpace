-- Reconciled 2026-11-20: applied to QA (ugwrpeduzyzrujkizqfo) on 2026-11-20 from
-- qa/activities-memories-two-scope-cutover-20261120:supabase/schema/0267_qa_media_purge_queue_source_provenance.sql (original number 0267). Kept verbatim so the
-- repository replays to the live QA schema. QA only; never apply to Production.
-- QA: a shared file can be queued only if its author belonged to the
-- relationship being erased. Prevents manipulated shared references from
-- deleting another person's file in the physical-purge worker.
ALTER TABLE public.qa_shared_media_purge_queue
 ADD COLUMN IF NOT EXISTS expected_uploader_id uuid;

CREATE OR REPLACE FUNCTION private.qa_purge_queue_source_guard()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $q$
DECLARE uploader uuid;storage_owner text;filename_owner text;
BEGIN
 IF tg_op='UPDATE' THEN
  IF new.space_id IS DISTINCT FROM old.space_id
    OR new.bucket_id IS DISTINCT FROM old.bucket_id
    OR new.object_path IS DISTINCT FROM old.object_path
    OR new.expected_uploader_id IS DISTINCT FROM old.expected_uploader_id THEN
   RAISE EXCEPTION 'Cannot change queued media identity or provenance'
    USING ERRCODE='42501';
  END IF;
  RETURN new;
 END IF;
 IF new.bucket_id IN('onespace-note-images','onespace-memory-photos',
   'onespace-trip-documents','onespace-activity-media','onespace-activity-voice')
  AND new.object_path !~ '^[0-9a-f-]{36}/[0-9a-f-]{36}/[0-9a-f-]{36}[.](jpg|jpeg|png|webp|m4a|pdf)$' THEN
   RAISE EXCEPTION 'Unsupported relationship media path' USING ERRCODE='42501';
 END IF;
 IF new.bucket_id='onespace-share-in' AND
   new.object_path !~ '^[0-9a-f-]{36}/[0-9a-f-]{36}[.](jpg|jpeg|png|webp|heic|pdf)$' THEN
   RAISE EXCEPTION 'Unsupported shared inbox media path' USING ERRCODE='42501';
 END IF;
 IF new.bucket_id='onespace-note-images' THEN
  SELECT i.created_by INTO uploader FROM public.note_images i
   JOIN public.notes parent ON parent.id=i.note_id
   WHERE i.object_path=new.object_path AND i.storage_bucket_id=new.bucket_id
    AND parent.space_id=new.space_id AND parent.private_space_id IS NULL;
 ELSIF new.bucket_id='onespace-memory-photos' THEN
  SELECT i.created_by INTO uploader FROM public.memory_photos i
   JOIN public.memories parent ON parent.id=i.memory_id
   WHERE i.object_path=new.object_path AND i.storage_bucket_id=new.bucket_id
    AND parent.space_id=new.space_id AND parent.private_space_id IS NULL;
 ELSIF new.bucket_id='onespace-trip-documents' THEN
  SELECT i.created_by INTO uploader FROM public.trip_attachments i
   JOIN public.shared_trips parent ON parent.id=i.trip_id
   WHERE i.object_path=new.object_path AND i.storage_bucket_id=new.bucket_id
    AND parent.space_id=new.space_id AND parent.private_space_id IS NULL;
 ELSIF new.bucket_id IN('onespace-activity-media','onespace-activity-voice') THEN
  SELECT nullif(o.owner_id,'')::uuid INTO uploader FROM storage.objects o
   JOIN public.activities a ON a.id::text=split_part(o.name,'/',1)
   WHERE o.bucket_id=new.bucket_id AND o.name=new.object_path
    AND a.space_id=new.space_id AND a.private_space_id IS NULL
    AND o.owner_id ~ '^[0-9a-f-]{36}$';
 ELSIF new.bucket_id='onespace-share-in' THEN
  SELECT i.created_by INTO uploader FROM public.items_to_sort i
   WHERE i.space_id=new.space_id AND i.private_space_id IS NULL
    AND i.file_path=new.object_path AND i.created_by::text=split_part(i.file_path,'/',1);
 ELSE
  RAISE EXCEPTION 'Unknown relationship media bucket' USING ERRCODE='42501';
 END IF;
 IF uploader IS NULL OR NOT EXISTS(SELECT 1 FROM public.space_members m
   WHERE m.space_id=new.space_id AND m.user_id=uploader) THEN
  RAISE EXCEPTION 'Queued shared file author is not a current member'
   USING ERRCODE='42501';
 END IF;
 filename_owner:=CASE WHEN new.bucket_id='onespace-share-in'
  THEN split_part(new.object_path,'/',1) ELSE split_part(new.object_path,'/',2) END;
 IF filename_owner<>uploader::text THEN
  RAISE EXCEPTION 'File prefix does not belong to its recorded author'
   USING ERRCODE='42501';
 END IF;
 SELECT o.owner_id INTO storage_owner FROM storage.objects o
  WHERE o.bucket_id=new.bucket_id AND o.name=new.object_path;
 IF storage_owner IS NOT NULL AND storage_owner<>uploader::text THEN
  RAISE EXCEPTION 'File object was uploaded by another account'
   USING ERRCODE='42501';
 END IF;
 new.expected_uploader_id:=uploader;
 RETURN new;
END $q$;
REVOKE ALL ON FUNCTION private.qa_purge_queue_source_guard() FROM PUBLIC,anon,authenticated;
DROP TRIGGER IF EXISTS qa_purge_source_guard ON public.qa_shared_media_purge_queue;
CREATE TRIGGER qa_purge_source_guard BEFORE INSERT OR UPDATE
 ON public.qa_shared_media_purge_queue FOR EACH ROW
 EXECUTE FUNCTION private.qa_purge_queue_source_guard();

-- Service leased reads include uploader for one more deletion-time check.
CREATE OR REPLACE FUNCTION public.qa_claim_shared_media_purge(p_limit integer DEFAULT 20)
RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $q$
DECLARE result jsonb;
BEGIN
 IF current_user<>'service_role' THEN
  RAISE EXCEPTION 'Service-only media cleanup' USING ERRCODE='42501';
 END IF;
 IF p_limit IS NULL OR p_limit<1 OR p_limit>50 THEN
  RAISE EXCEPTION 'Invalid purge batch size' USING ERRCODE='22023';
 END IF;
 WITH eligible AS(
  SELECT q.space_id,q.bucket_id,q.object_path
  FROM public.qa_shared_media_purge_queue q
  WHERE q.deleted_at IS NULL AND q.expected_uploader_id IS NOT NULL
   AND (q.leased_at IS NULL OR q.leased_at<now()-interval '5 minutes')
   AND NOT EXISTS(SELECT 1 FROM public.spaces s WHERE s.id=q.space_id)
   -- Fail closed if an object was re-owned after the trusted queue snapshot.
   AND NOT EXISTS(SELECT 1 FROM storage.objects o
     WHERE o.bucket_id=q.bucket_id AND o.name=q.object_path
       AND o.owner_id IS DISTINCT FROM q.expected_uploader_id::text)
   -- If a live item elsewhere still references this exact object, the worker
   -- may not delete it as part of a different relationship's cleanup.
   AND NOT EXISTS(SELECT 1 FROM public.note_images n
     WHERE q.bucket_id='onespace-note-images'
       AND n.storage_bucket_id=q.bucket_id AND n.object_path=q.object_path)
   AND NOT EXISTS(SELECT 1 FROM public.memory_photos m
     WHERE q.bucket_id='onespace-memory-photos'
       AND m.storage_bucket_id=q.bucket_id AND m.object_path=q.object_path)
   AND NOT EXISTS(SELECT 1 FROM public.trip_attachments t
     WHERE q.bucket_id='onespace-trip-documents'
       AND t.storage_bucket_id=q.bucket_id AND t.object_path=q.object_path)
   AND NOT EXISTS(SELECT 1 FROM public.items_to_sort i
     WHERE q.bucket_id='onespace-share-in' AND i.file_path=q.object_path)
   AND NOT EXISTS(SELECT 1 FROM public.activity_components c
     WHERE q.bucket_id='onespace-activity-media'
       AND (c.payload->>'object_path')=q.object_path)
   AND NOT EXISTS(SELECT 1 FROM public.activity_comments cm
     WHERE q.bucket_id='onespace-activity-voice' AND cm.voice_path=q.object_path)
  ORDER BY q.queued_at,q.space_id,q.bucket_id,q.object_path
  FOR UPDATE OF q SKIP LOCKED LIMIT p_limit
 ), leased AS(
  UPDATE public.qa_shared_media_purge_queue q
   SET lease_id=gen_random_uuid(),leased_at=now(),
       attempts=q.attempts+1,last_error=NULL
  FROM eligible x
  WHERE q.space_id=x.space_id AND q.bucket_id=x.bucket_id
    AND q.object_path=x.object_path
  RETURNING q.space_id,q.bucket_id,q.object_path,q.lease_id,
    q.attempts,q.expected_uploader_id
 )
 SELECT coalesce(jsonb_agg(jsonb_build_object(
   'space_id',x.space_id,'bucket_id',x.bucket_id,
   'object_path',x.object_path,'lease_id',x.lease_id,
   'attempts',x.attempts,'expected_uploader_id',x.expected_uploader_id)),
   '[]'::jsonb) INTO result FROM leased x;
 RETURN result;
END $q$;
REVOKE ALL ON FUNCTION public.qa_claim_shared_media_purge(integer)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.qa_claim_shared_media_purge(integer) TO service_role;
