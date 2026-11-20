-- QA ONLY: close the multi-request race between read-only readiness,
-- media audit scrub, cancellation/pairing and the external Auth Admin API.
-- Once claimed, processing is sticky and cannot be automatically retried.
-- Admin must manually reconcile a failed Auth deletion. No QA gate is opened.
ALTER TABLE public.account_deletion_requests
 ADD COLUMN IF NOT EXISTS finalization_claim_id uuid;

CREATE OR REPLACE FUNCTION public.qa_claim_account_for_auth_finalization(p_user uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $q$
DECLARE record_request record; before_readiness jsonb;after_readiness jsonb;
      scrubbed jsonb;claimed uuid:=gen_random_uuid();changed integer;
BEGIN
 IF current_user<>'service_role' THEN
  RAISE EXCEPTION 'Only trusted service may claim account finalization'
   USING ERRCODE='42501';
 END IF;
 IF p_user IS NULL THEN RAISE EXCEPTION 'Account id required' USING ERRCODE='22023';END IF;
 -- Pair/invite/cancel use precisely this lock namespace.
 PERFORM pg_advisory_xact_lock(hashtextextended(p_user::text,5));
 SELECT r.purge_after,r.cancelled_at,r.completed_at,r.processing_at,
        r.finalization_claim_id INTO record_request
 FROM public.account_deletion_requests r WHERE r.user_id=p_user FOR UPDATE;
 IF NOT FOUND OR record_request.cancelled_at IS NOT NULL
  OR record_request.completed_at IS NOT NULL
  OR record_request.processing_at IS NOT NULL
  OR record_request.finalization_claim_id IS NOT NULL
  OR record_request.purge_after>now() THEN
  RAISE EXCEPTION 'Account is not eligible for first and only finalization claim'
   USING ERRCODE='42501';
 END IF;
 before_readiness:=public.qa_account_final_deletion_readiness(p_user);
 IF before_readiness->>'ready_for_auth_delete'<>'true' THEN
  RAISE EXCEPTION 'Cannot claim account: shared/private data or Storage objects remain'
   USING ERRCODE='42501';
 END IF;
 -- Atomic with readiness + claim; rollback restores completed metadata on fail.
 scrubbed:=public.qa_scrub_completed_account_media_jobs(p_user);
 after_readiness:=public.qa_account_final_deletion_readiness(p_user);
 IF after_readiness->>'ready_for_auth_delete'<>'true' THEN
  RAISE EXCEPTION 'Post-scrub final deletion readiness changed'
   USING ERRCODE='42501';
 END IF;
 UPDATE public.account_deletion_requests r
  SET processing_at=now(),finalization_claim_id=claimed,last_error=NULL
 WHERE r.user_id=p_user AND r.processing_at IS NULL AND r.cancelled_at IS NULL
   AND r.completed_at IS NULL AND r.finalization_claim_id IS NULL
   AND r.purge_after<=now();
 GET DIAGNOSTICS changed=ROW_COUNT;
 IF changed<>1 THEN RAISE EXCEPTION 'Concurrent finalization or cancellation'
    USING ERRCODE='42501'; END IF;
 RETURN jsonb_build_object('claimed',true,'user_id',p_user,
  'claim_id',claimed,'readiness',after_readiness,'scrub',scrubbed);
END $q$;
REVOKE ALL ON FUNCTION public.qa_claim_account_for_auth_finalization(uuid)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.qa_claim_account_for_auth_finalization(uuid)
 TO service_role;

-- A claim is not an advisory lock spanning HTTP requests. Instead the
-- processed request becomes an immutable DB fence; all normal client DML
-- on supported public user-writable tables is denied through a trigger.
CREATE OR REPLACE FUNCTION private.qa_is_account_in_finalization(p_user uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $q$
 SELECT p_user IS NOT NULL AND auth.uid()=p_user AND EXISTS(
 SELECT 1 FROM public.account_deletion_requests r
 WHERE r.user_id=p_user AND r.processing_at IS NOT NULL
 AND r.finalization_claim_id IS NOT NULL
 AND r.cancelled_at IS NULL AND r.completed_at IS NULL);
$q$;
REVOKE ALL ON FUNCTION private.qa_is_account_in_finalization(uuid)
 FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION private.qa_is_account_in_finalization(uuid)
 TO authenticated;

CREATE OR REPLACE FUNCTION private.qa_reject_finalizing_user_writes()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $q$
BEGIN
 -- Authenticated client DML only; backend cascade, service cleanup and
 -- the privileged Auth Admin path remain unaffected.
 IF current_user='authenticated' AND auth.uid() IS NOT NULL
   AND private.qa_is_account_in_finalization(auth.uid()) THEN
  RAISE EXCEPTION 'Account finalization has started; content changes are disabled'
   USING ERRCODE='42501';
 END IF;
 IF TG_OP='DELETE' THEN RETURN OLD;END IF;
 RETURN NEW;
END $q$;
REVOKE ALL ON FUNCTION private.qa_reject_finalizing_user_writes()
 FROM PUBLIC,anon,authenticated;
-- Guard all public tables that the authenticated role can directly mutate,
-- not just the 24 private roots. Do not touch Auth/Storage internal tables.
DO $installer$
DECLARE t record;
BEGIN
 FOR t IN
  SELECT c.relname
  FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname='public' AND c.relkind IN('r','p')
   AND (has_table_privilege('authenticated',c.oid,'INSERT')
    OR has_table_privilege('authenticated',c.oid,'UPDATE')
    OR has_table_privilege('authenticated',c.oid,'DELETE'))
  ORDER BY c.relname
 LOOP
  EXECUTE format('DROP TRIGGER IF EXISTS qa_finalization_write_fence ON public.%I',
   t.relname);
  EXECUTE format('CREATE TRIGGER qa_finalization_write_fence
    BEFORE INSERT OR UPDATE OR DELETE ON public.%I FOR EACH ROW
    EXECUTE FUNCTION private.qa_reject_finalizing_user_writes()',t.relname);
 END LOOP;
END $installer$;
