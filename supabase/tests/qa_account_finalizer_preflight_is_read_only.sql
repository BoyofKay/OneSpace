-- QA rollback: due-account FK report cannot finalize a real account.
BEGIN;
SELECT set_config('qa.user',(SELECT user_id::text FROM public.space_members ORDER BY space_id,user_id LIMIT 1),true);
INSERT INTO public.account_deletion_requests(user_id,requested_at,purge_after)
VALUES(current_setting('qa.user')::uuid,now()-interval '8 days',now()-interval '1 day');
SELECT set_config('request.jwt.claim.sub',current_setting('qa.user'),true);
SET LOCAL ROLE authenticated;
DO $app$
BEGIN
 BEGIN
  PERFORM public.qa_account_finalizer_preflight(current_setting('qa.user')::uuid);
  RAISE EXCEPTION 'BUG: normal app user can run admin Auth FK preflight';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM LIKE 'BUG:%' THEN RAISE;END IF;END;
END $app$;
RESET ROLE;
SET LOCAL ROLE service_role;
DO $service$
DECLARE result jsonb;cnt integer;
BEGIN
 result:=public.qa_account_finalizer_preflight(current_setting('qa.user')::uuid);
 IF result->>'due'<>'true' OR result->>'private_namespace_exists'<>'true'
  OR result->>'ready_for_destructive_finalization'<>'false' THEN
   RAISE EXCEPTION 'Due-account preflight eligibility/safety contract wrong';
 END IF;
 SELECT count(*) INTO cnt FROM public.user_private_spaces
 WHERE owner_id=current_setting('qa.user')::uuid;
 IF cnt<>1 THEN RAISE EXCEPTION 'Read-only preflight deleted private namespace';END IF;
 SELECT count(*) INTO cnt FROM auth.users WHERE id=current_setting('qa.user')::uuid;
 IF cnt<>1 THEN RAISE EXCEPTION 'Read-only preflight deleted Auth user';END IF;
END $service$;
ROLLBACK;
SELECT 'PASS account finalizer service-only counts due/Auth FK orphan blocks, no account or personal-content deletion; rolled back' result;