-- Reconciled 2026-11-20: applied to QA (ugwrpeduzyzrujkizqfo) on 2026-11-20 from
-- qa/activities-memories-two-scope-cutover-20261120:supabase/schema/0266_qa_shared_media_purge_claim_and_ack.sql (original number 0266). Kept verbatim so the
-- repository replays to the live QA schema. QA only; never apply to Production.
-- QA staging only: trusted Storage-purge worker leases and acknowledges jobs.
-- These RPCs are callable only by service_role. No app user can list,
-- claim, change or delete a queued file.
ALTER TABLE public.qa_shared_media_purge_queue
  ADD COLUMN IF NOT EXISTS lease_id uuid;
ALTER TABLE public.qa_shared_media_purge_queue
  ADD COLUMN IF NOT EXISTS leased_at timestamptz;
ALTER TABLE public.qa_shared_media_purge_queue
  ADD COLUMN IF NOT EXISTS attempts integer NOT NULL DEFAULT 0
    CHECK(attempts>=0);

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
 -- Old live spaces must NEVER be touched, even if the queue was filled in
 -- error by an integration. Only a fully retired relationship may be purged.
 WITH eligible AS (
  SELECT q.space_id,q.bucket_id,q.object_path
  FROM public.qa_shared_media_purge_queue q
  WHERE q.deleted_at IS NULL
    AND (q.leased_at IS NULL OR q.leased_at<now()-interval '5 minutes')
    AND NOT EXISTS(SELECT 1 FROM public.spaces s WHERE s.id=q.space_id)
  ORDER BY q.queued_at,q.space_id,q.bucket_id,q.object_path
  FOR UPDATE OF q SKIP LOCKED
  LIMIT p_limit
 ), leased AS (
  UPDATE public.qa_shared_media_purge_queue q
  SET lease_id=gen_random_uuid(),leased_at=now(),
      attempts=q.attempts+1,last_error=NULL
  FROM eligible x
  WHERE q.space_id=x.space_id AND q.bucket_id=x.bucket_id
    AND q.object_path=x.object_path
  RETURNING q.space_id,q.bucket_id,q.object_path,q.lease_id,q.attempts
 )
 SELECT coalesce(jsonb_agg(jsonb_build_object(
   'space_id',x.space_id,'bucket_id',x.bucket_id,
   'object_path',x.object_path,'lease_id',x.lease_id,
   'attempts',x.attempts)), '[]'::jsonb) INTO result
 FROM leased x;
 RETURN result;
END $q$;

CREATE OR REPLACE FUNCTION public.qa_ack_shared_media_purge(
 p_space_id uuid,p_bucket_id text,p_object_path text,
 p_lease_id uuid,p_succeeded boolean)
RETURNS boolean LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $q$
DECLARE changed integer;
BEGIN
 IF current_user<>'service_role' THEN
  RAISE EXCEPTION 'Service-only media cleanup' USING ERRCODE='42501';
 END IF;
 IF p_space_id IS NULL OR p_bucket_id IS NULL OR p_object_path IS NULL
  OR p_lease_id IS NULL OR p_succeeded IS NULL THEN
  RAISE EXCEPTION 'Complete cleanup acknowledgement required'
    USING ERRCODE='22023';
 END IF;
 UPDATE public.qa_shared_media_purge_queue q SET
  deleted_at=CASE WHEN p_succeeded THEN now() ELSE NULL END,
  last_error=CASE WHEN p_succeeded THEN NULL ELSE 'storage_api_remove_failed' END,
  leased_at=NULL,lease_id=NULL
 WHERE q.space_id=p_space_id AND q.bucket_id=p_bucket_id
   AND q.object_path=p_object_path AND q.lease_id=p_lease_id
   AND q.deleted_at IS NULL
   AND NOT EXISTS(SELECT 1 FROM public.spaces s WHERE s.id=p_space_id);
 GET DIAGNOSTICS changed=ROW_COUNT;
 RETURN changed=1;
END $q$;
REVOKE ALL ON FUNCTION public.qa_claim_shared_media_purge(integer)
 FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.qa_ack_shared_media_purge(uuid,text,text,uuid,boolean)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.qa_claim_shared_media_purge(integer) TO service_role;
GRANT EXECUTE ON FUNCTION public.qa_ack_shared_media_purge(uuid,text,text,uuid,boolean)
 TO service_role;
