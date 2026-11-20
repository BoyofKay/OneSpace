-- QA-only account deletion grace-period foundation.
-- The finalizer remains OFF and the request RPC remains revoked until
-- survivor-preserving shared erasure, personal purge, Storage and Auth cleanup
-- have been implemented and acceptance-tested.
ALTER TABLE public.account_deletion_requests
 ADD COLUMN IF NOT EXISTS processing_at timestamptz;
ALTER TABLE public.account_deletion_requests ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Read my deletion request" ON public.account_deletion_requests;
CREATE POLICY "Read my deletion request" ON public.account_deletion_requests
 FOR SELECT TO authenticated USING(user_id=(select auth.uid()));
REVOKE ALL ON public.account_deletion_requests FROM PUBLIC,anon,authenticated;
GRANT SELECT(user_id,requested_at,purge_after,cancelled_at,completed_at,processing_at)
 ON public.account_deletion_requests TO authenticated;

CREATE OR REPLACE FUNCTION public.request_account_deletion()
RETURNS timestamptz LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $q$
DECLARE me uuid:=auth.uid(); due timestamptz;
BEGIN
 IF me IS NULL THEN RAISE EXCEPTION 'Sign in to request deletion' USING ERRCODE='42501';END IF;
 INSERT INTO public.account_deletion_requests(user_id,requested_at,purge_after,
  cancelled_at,completed_at,last_error,processing_at)
 VALUES(me,now(),now()+interval '7 days',NULL,NULL,NULL,NULL)
 ON CONFLICT(user_id) DO UPDATE SET
  requested_at=CASE WHEN account_deletion_requests.cancelled_at IS NULL
    AND account_deletion_requests.completed_at IS NULL
    THEN account_deletion_requests.requested_at ELSE now() END,
  purge_after=CASE WHEN account_deletion_requests.cancelled_at IS NULL
    AND account_deletion_requests.completed_at IS NULL
    THEN account_deletion_requests.purge_after ELSE now()+interval '7 days' END,
  cancelled_at=NULL,
  last_error=NULL
 WHERE account_deletion_requests.processing_at IS NULL
   AND account_deletion_requests.completed_at IS NULL
 RETURNING purge_after INTO due;
 IF due IS NULL THEN
  RAISE EXCEPTION 'Account deletion cannot be re-requested once finalization begins'
    USING ERRCODE='42501';
 END IF;
 RETURN due;
END $q$;

CREATE OR REPLACE FUNCTION public.cancel_account_deletion()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $q$
DECLARE me uuid:=auth.uid(); stopped integer;
BEGIN
 IF me IS NULL THEN RAISE EXCEPTION 'Sign in to cancel deletion' USING ERRCODE='42501';END IF;
 UPDATE public.account_deletion_requests
  SET cancelled_at=now(),last_error=NULL
  WHERE user_id=me AND cancelled_at IS NULL AND completed_at IS NULL
    AND processing_at IS NULL AND purge_after>now();
 GET DIAGNOSTICS stopped=ROW_COUNT;
 IF stopped=0 AND EXISTS(SELECT 1 FROM public.account_deletion_requests
  WHERE user_id=me AND cancelled_at IS NULL AND completed_at IS NULL) THEN
  RAISE EXCEPTION 'The seven-day cancellation window has ended or processing started'
   USING ERRCODE='42501';
 END IF;
END $q$;

CREATE OR REPLACE FUNCTION public.my_account_deletion_status()
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path='' AS $q$
SELECT coalesce((
 SELECT jsonb_build_object(
  'state',CASE
   WHEN r.completed_at IS NOT NULL THEN 'completed'
   WHEN r.cancelled_at IS NOT NULL THEN 'cancelled'
   WHEN r.processing_at IS NOT NULL THEN 'processing'
   WHEN r.purge_after<=now() THEN 'due'
   ELSE 'pending' END,
  'requested_at',r.requested_at,'purge_after',r.purge_after,
  'can_cancel',r.cancelled_at IS NULL AND r.completed_at IS NULL
    AND r.processing_at IS NULL AND r.purge_after>now())
 FROM public.account_deletion_requests r
 WHERE r.user_id=(select auth.uid())
),jsonb_build_object('state','none','can_cancel',false));
$q$;

REVOKE ALL ON FUNCTION public.request_account_deletion() FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.my_account_deletion_status() FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.my_account_deletion_status() TO authenticated;
REVOKE ALL ON FUNCTION public.cancel_account_deletion() FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.cancel_account_deletion() TO authenticated;
-- Do not modify purge_due_accounts_list or purge_account_data_service; both
-- remain disabled/fail-closed until the true finalizer is independently verified.
