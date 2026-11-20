-- QA: include personally authored Activity media and M4A voice in the
-- seven-day account-deletion file inventory; no real deletion is enabled.
ALTER TABLE public.qa_account_private_media_purge_queue
 DROP CONSTRAINT IF EXISTS qa_account_private_media_purge_queue_bucket_id_check;
ALTER TABLE public.qa_account_private_media_purge_queue
 ADD CONSTRAINT qa_account_private_media_purge_queue_bucket_id_check
 CHECK(bucket_id IN('onespace-private-note-images',
 'onespace-private-memory-photos','onespace-private-trip-documents',
 'onespace-private-share-in','onespace-private-activity-media',
 'onespace-private-activity-voice')) NOT VALID;
CREATE OR REPLACE FUNCTION private.qa_inventory_due_private_media(p_user uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $q$
DECLARE deadline timestamptz;found_rows integer;queued integer;
BEGIN
 IF current_user<>'service_role' THEN
  RAISE EXCEPTION 'Service-only due account inventory' USING ERRCODE='42501';
 END IF;
 IF NOT EXISTS(SELECT 1 FROM private.qa_account_v2_gate
   WHERE id=1 AND enabled) THEN
  RAISE EXCEPTION 'Account purge inventory is not enabled'
    USING ERRCODE='42501';
 END IF;
 IF p_user IS NULL THEN
  RAISE EXCEPTION 'Target user required' USING ERRCODE='22023';
 END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(p_user::text,1));
 SELECT r.purge_after INTO deadline
 FROM public.account_deletion_requests r
 WHERE r.user_id=p_user AND r.cancelled_at IS NULL
   AND r.completed_at IS NULL AND r.purge_after<=now()
   AND r.processing_at IS NULL
 FOR UPDATE;
 IF deadline IS NULL THEN
  RAISE EXCEPTION 'Account is not eligible after its full seven-day grace'
   USING ERRCODE='42501';
 END IF;
 IF NOT EXISTS(SELECT 1 FROM public.user_private_spaces p
   WHERE p.owner_id=p_user) THEN
  RAISE EXCEPTION 'Personal scope missing: halt purge'
   USING ERRCODE='42501';
 END IF;
 INSERT INTO public.qa_account_private_media_purge_queue(
   owner_id,bucket_id,object_path)
 SELECT p_user,o.bucket_id,o.name FROM storage.objects o
 WHERE o.bucket_id IN('onespace-private-note-images',
  'onespace-private-memory-photos','onespace-private-trip-documents',
  'onespace-private-share-in',
  'onespace-private-activity-media','onespace-private-activity-voice')
 AND o.owner_id=p_user::text
 AND ((
    o.bucket_id='onespace-private-share-in'
    AND split_part(o.name,'/',1)=p_user::text
    AND o.name ~ '^[0-9a-f-]{36}/[0-9a-f-]{36}[.](jpg|jpeg|png|webp|heic|pdf)$'
   ) OR (
    o.bucket_id<>'onespace-private-share-in'
    AND split_part(o.name,'/',2)=p_user::text
    AND o.name ~ '^[0-9a-f-]{36}/[0-9a-f-]{36}/[0-9a-f-]{36}[.](jpg|jpeg|png|webp|m4a|pdf)$'
   ))
 ON CONFLICT DO NOTHING;
 SELECT count(*) INTO queued
 FROM public.qa_account_private_media_purge_queue q
 WHERE q.owner_id=p_user AND q.deleted_at IS NULL;
 SELECT count(*) INTO found_rows
 FROM storage.objects o
 WHERE o.owner_id=p_user::text AND o.bucket_id IN(
 'onespace-private-note-images','onespace-private-memory-photos',
 'onespace-private-trip-documents','onespace-private-share-in',
 'onespace-private-activity-media','onespace-private-activity-voice');
 IF queued<>found_rows THEN
  RAISE EXCEPTION 'Account private Storage inventory incomplete: no deletion permitted'
   USING ERRCODE='42501';
 END IF;
 RETURN jsonb_build_object('eligible',true,'owner_id',p_user,
   'files_queued',queued,'due_at',deadline,
   'next_step','not_activated; verify Auth foreign keys and physical removal');
END $q$;
REVOKE ALL ON FUNCTION private.qa_inventory_due_private_media(uuid)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION private.qa_inventory_due_private_media(uuid)
 TO service_role;
