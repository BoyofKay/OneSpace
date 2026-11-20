-- Reconciled 2026-11-20: applied to QA (ugwrpeduzyzrujkizqfo) on 2026-11-20 from
-- qa/activities-memories-two-scope-cutover-20261120:supabase/schema/0283_qa_completed_account_media_audit_scrub.sql (original number 0283). Kept verbatim so the
-- repository replays to the live QA schema. QA only; never apply to Production.
-- QA ONLY. Do not retain account identifiers in completed file-purge
-- queues after physically erasing every owned file and verifying eligibility.
-- Never clear an uncompleted job or allow ordinary app users to invoke.
GRANT DELETE ON public.qa_account_private_media_purge_queue TO service_role;
GRANT DELETE ON public.qa_shared_media_purge_queue TO service_role;
CREATE OR REPLACE FUNCTION public.qa_scrub_completed_account_media_jobs(p_user uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $q$
DECLARE verified jsonb;own_count integer;shared_count integer;
BEGIN
 IF current_user<>'service_role' THEN
  RAISE EXCEPTION 'Service-only completed account media audit cleanup'
   USING ERRCODE='42501';
 END IF;
 IF p_user IS NULL THEN RAISE EXCEPTION 'Owner required' USING ERRCODE='22023';END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(p_user::text,1));
 verified:=public.qa_account_final_deletion_readiness(p_user);
 IF verified->>'ready_for_auth_delete'<>'true' THEN
  RAISE EXCEPTION 'Cannot clear any audit while account deletion prerequisites remain'
   USING ERRCODE='42501';
 END IF;
 DELETE FROM public.qa_account_private_media_purge_queue q
 WHERE q.owner_id=p_user AND q.deleted_at IS NOT NULL;
 GET DIAGNOSTICS own_count=ROW_COUNT;
 DELETE FROM public.qa_shared_media_purge_queue q
 WHERE q.expected_uploader_id=p_user AND q.deleted_at IS NOT NULL;
 GET DIAGNOSTICS shared_count=ROW_COUNT;
 RETURN jsonb_build_object('completed_private_jobs_scrubbed',own_count,
  'completed_shared_jobs_scrubbed',shared_count,
  'account_user_deleted',false);
END $q$;
REVOKE ALL ON FUNCTION public.qa_scrub_completed_account_media_jobs(uuid)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.qa_scrub_completed_account_media_jobs(uuid)
 TO service_role;
