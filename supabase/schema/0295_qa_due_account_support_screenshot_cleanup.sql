-- Reconciled 2026-11-20: applied to QA (ugwrpeduzyzrujkizqfo) on 2026-11-20 from
-- qa/activities-memories-two-scope-cutover-20261120:supabase/schema/0288_qa_due_account_support_screenshot_cleanup.sql (original number 0288). Kept verbatim so the
-- repository replays to the live QA schema. QA only; never apply to Production.
-- QA account deletion: include owner-only technical-support screenshot
-- files (ownerUUID/timestamp.jpg or .png). Supabase Auth cannot delete users
-- while these owned objects remain. No Storage API worker is deployed.
ALTER TABLE public.qa_account_private_media_purge_queue
 DROP CONSTRAINT IF EXISTS qa_account_private_media_purge_queue_bucket_id_check;
ALTER TABLE public.qa_account_private_media_purge_queue
 ADD CONSTRAINT qa_account_private_media_purge_queue_bucket_id_check
 CHECK(bucket_id IN('onespace-private-note-images',
 'onespace-private-memory-photos','onespace-private-trip-documents',
 'onespace-private-share-in','onespace-private-activity-media',
 'onespace-private-activity-voice','onespace-support')) NOT VALID;
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
  'onespace-private-activity-media','onespace-private-activity-voice','onespace-support')
 AND o.owner_id=p_user::text
 AND ((
    o.bucket_id='onespace-private-share-in'
    AND split_part(o.name,'/',1)=p_user::text
    AND o.name ~ '^[0-9a-f-]{36}/[0-9a-f-]{36}[.](jpg|jpeg|png|webp|heic|pdf)$'
   ) OR (
    o.bucket_id='onespace-support'
    AND split_part(o.name,'/',1)=p_user::text
    AND o.name ~ '^[0-9a-f-]{36}/[0-9]{13}[.](png|jpg)$'
   ) OR (
    o.bucket_id NOT IN('onespace-private-share-in','onespace-support')
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
 'onespace-private-activity-media','onespace-private-activity-voice','onespace-support');
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

-- QA ONLY. Claim/acknowledge a due account's OWN media after disconnection.
-- SAFE BY DEFAULT: account purge gate remains OFF, app EXECUTE revoked.
-- The file worker must use Storage API remove, never DELETE storage.objects.
CREATE OR REPLACE FUNCTION public.qa_claim_due_account_private_media(p_limit integer DEFAULT 20)
RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $q$
DECLARE result jsonb;
BEGIN
 IF current_user<>'service_role' THEN
  RAISE EXCEPTION 'Service-only account media purge' USING ERRCODE='42501';
 END IF;
 IF NOT EXISTS(SELECT 1 FROM private.qa_account_v2_gate
     WHERE id=1 AND enabled) THEN
  RAISE EXCEPTION 'Account media purge gate closed' USING ERRCODE='42501';
 END IF;
 IF p_limit IS NULL OR p_limit<1 OR p_limit>50 THEN
  RAISE EXCEPTION 'Invalid account media purge batch size' USING ERRCODE='22023';
 END IF;
 WITH eligible AS (
  SELECT q.owner_id,q.bucket_id,q.object_path
  FROM public.qa_account_private_media_purge_queue q
  JOIN public.account_deletion_requests r ON r.user_id=q.owner_id
  WHERE q.deleted_at IS NULL
    AND (q.leased_at IS NULL OR q.leased_at<now()-interval '5 minutes')
    AND r.cancelled_at IS NULL AND r.completed_at IS NULL
    AND r.purge_after<=now() AND r.processing_at IS NULL
    -- Never purge files while a pair or a creator-owned space still exists.
    AND NOT EXISTS(SELECT 1 FROM public.space_members m WHERE m.user_id=q.owner_id)
    AND NOT EXISTS(SELECT 1 FROM public.spaces s WHERE s.created_by=q.owner_id)
    AND EXISTS(SELECT 1 FROM public.user_private_spaces p WHERE p.owner_id=q.owner_id)
    -- A valid queue must never delete a file whose Storage owner has changed.
    AND NOT EXISTS(SELECT 1 FROM storage.objects o
      WHERE o.bucket_id=q.bucket_id AND o.name=q.object_path
        AND o.owner_id IS DISTINCT FROM q.owner_id::text)
    -- Keep the account's original folder attribution in every lease.
    AND ((
      q.bucket_id='onespace-private-share-in'
      AND split_part(q.object_path,'/',1)=q.owner_id::text
      AND q.object_path ~ '^[0-9a-f-]{36}/[0-9a-f-]{36}[.](jpg|jpeg|png|webp|heic|pdf)$'
    ) OR (
      q.bucket_id='onespace-support'
      AND split_part(q.object_path,'/',1)=q.owner_id::text
      AND q.object_path ~ '^[0-9a-f-]{36}/[0-9]{13}[.](png|jpg)$'
    ) OR (
      q.bucket_id NOT IN('onespace-private-share-in','onespace-support')
      AND split_part(q.object_path,'/',2)=q.owner_id::text
      AND q.object_path ~ '^[0-9a-f-]{36}/[0-9a-f-]{36}/[0-9a-f-]{36}[.](jpg|jpeg|png|webp|m4a|pdf)$'
    ))
  ORDER BY q.queued_at,q.owner_id,q.bucket_id,q.object_path
  FOR UPDATE OF q SKIP LOCKED LIMIT p_limit
 ), leased AS (
  UPDATE public.qa_account_private_media_purge_queue q
    SET lease_id=gen_random_uuid(),leased_at=now(),attempts=q.attempts+1,
        last_error=NULL
  FROM eligible e
  WHERE q.owner_id=e.owner_id AND q.bucket_id=e.bucket_id
    AND q.object_path=e.object_path
  RETURNING q.owner_id,q.bucket_id,q.object_path,q.lease_id,q.attempts
 )
 SELECT coalesce(jsonb_agg(jsonb_build_object(
  'owner_id',x.owner_id,'bucket_id',x.bucket_id,'object_path',x.object_path,
  'lease_id',x.lease_id,'attempts',x.attempts)),'[]'::jsonb)
 INTO result FROM leased x;
 RETURN result;
END $q$;

CREATE OR REPLACE FUNCTION public.qa_ack_due_account_private_media(
 p_owner_id uuid,p_bucket_id text,p_object_path text,
 p_lease_id uuid,p_succeeded boolean)
RETURNS boolean LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $q$
DECLARE affected integer;
BEGIN
 IF current_user<>'service_role' THEN
  RAISE EXCEPTION 'Service-only account media purge' USING ERRCODE='42501';
 END IF;
 IF NOT EXISTS(SELECT 1 FROM private.qa_account_v2_gate
     WHERE id=1 AND enabled) THEN
  RAISE EXCEPTION 'Account media purge gate closed' USING ERRCODE='42501';
 END IF;
 IF p_owner_id IS NULL OR p_bucket_id IS NULL OR p_object_path IS NULL
    OR p_lease_id IS NULL OR p_succeeded IS NULL THEN
  RAISE EXCEPTION 'Complete owner media lease acknowledgement is required'
   USING ERRCODE='22023';
 END IF;
 UPDATE public.qa_account_private_media_purge_queue q SET
  deleted_at=CASE WHEN p_succeeded THEN now() ELSE NULL END,
  last_error=CASE WHEN p_succeeded THEN NULL ELSE 'storage_api_remove_failed' END,
  lease_id=NULL,leased_at=NULL
 WHERE q.owner_id=p_owner_id AND q.bucket_id=p_bucket_id
  AND q.object_path=p_object_path AND q.lease_id=p_lease_id
  AND q.deleted_at IS NULL
  AND EXISTS(SELECT 1 FROM public.account_deletion_requests r
   WHERE r.user_id=q.owner_id AND r.cancelled_at IS NULL
      AND r.completed_at IS NULL AND r.purge_after<=now()
      AND r.processing_at IS NULL)
  AND NOT EXISTS(SELECT 1 FROM public.space_members m WHERE m.user_id=q.owner_id)
  AND NOT EXISTS(SELECT 1 FROM public.spaces s WHERE s.created_by=q.owner_id);
 GET DIAGNOSTICS affected=ROW_COUNT;
 RETURN affected=1;
END $q$;
REVOKE ALL ON FUNCTION public.qa_claim_due_account_private_media(integer)
 FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.qa_ack_due_account_private_media(uuid,text,text,uuid,boolean)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.qa_claim_due_account_private_media(integer)
 TO service_role;
GRANT EXECUTE ON FUNCTION public.qa_ack_due_account_private_media(uuid,text,text,uuid,boolean)
 TO service_role;
