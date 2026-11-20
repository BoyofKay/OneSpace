-- Reconciled 2026-11-20: applied to QA (ugwrpeduzyzrujkizqfo) on 2026-11-20 from
-- qa/activities-memories-two-scope-cutover-20261120:supabase/schema/0276_qa_due_account_personal_media_worker_leases.sql (original number 0276). Kept verbatim so the
-- repository replays to the live QA schema. QA only; never apply to Production.
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
      q.bucket_id<>'onespace-private-share-in'
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
