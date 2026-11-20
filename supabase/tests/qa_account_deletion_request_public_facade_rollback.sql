-- QA rollback: authentic request through public gated facade is limited
-- to existing actor, exactly 7 days, idempotent, cancellable, re-requestable.
BEGIN;
SELECT set_config('qa.user',gen_random_uuid()::text,true);
INSERT INTO auth.users(id,aud,role,email,encrypted_password,email_confirmed_at)
VALUES(current_setting('qa.user')::uuid,'authenticated','authenticated',
 'qa-request-facade-'||current_setting('qa.user')||'@example.invalid','synthetic',now());
SELECT set_config('request.jwt.claim.sub',current_setting('qa.user'),true);
SET LOCAL ROLE authenticated;
DO $closed$
BEGIN
 BEGIN
  PERFORM public.qa_request_account_deletion();
  RAISE EXCEPTION 'BUG: account scheduled while QA lifecycle gate off';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM LIKE 'BUG:%' THEN RAISE;END IF;END;
END $closed$;
RESET ROLE;
UPDATE private.qa_account_v2_gate SET enabled=true WHERE id=1;
SET LOCAL ROLE authenticated;
DO $open$
DECLARE first_due timestamptz; second_due timestamptz;
BEGIN
 first_due:=public.qa_request_account_deletion();
 IF first_due<=now()+interval '6 days 23 hours'
  OR first_due>=now()+interval '7 days 1 hour' THEN
  RAISE EXCEPTION 'Account cancellation window is not seven days';END IF;
 second_due:=public.qa_request_account_deletion();
 IF second_due IS DISTINCT FROM first_due THEN
  RAISE EXCEPTION 'Repeated request extended or shortened grace';END IF;
 PERFORM public.cancel_account_deletion();
 IF EXISTS(SELECT 1 FROM public.account_deletion_requests
 WHERE user_id=current_setting('qa.user')::uuid
  AND cancelled_at IS NULL AND completed_at IS NULL) THEN
  RAISE EXCEPTION 'Cancel did not restore account';END IF;
 second_due:=public.qa_request_account_deletion();
 -- PostgreSQL now() is transaction-stable. In this single rollback
 -- transaction the recomputed 7-day date equals the first date by design.
 -- Check that the request has actually been REACTIVATED, not just returned.
 IF second_due IS DISTINCT FROM now()+interval '7 days' OR NOT EXISTS(
  SELECT 1 FROM public.account_deletion_requests
  WHERE user_id=current_setting('qa.user')::uuid
   AND cancelled_at IS NULL AND completed_at IS NULL
   AND processing_at IS NULL AND purge_after=second_due
 ) THEN
  RAISE EXCEPTION 'Cancelled account was not re-scheduled';END IF;
END $open$;
RESET ROLE;
ROLLBACK;
SELECT 'PASS request gate-off, authenticated exactly-seven-day scheduling, repeat idempotence, cancellation and fresh request; no persisted record' result;