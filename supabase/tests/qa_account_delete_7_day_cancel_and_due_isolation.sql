-- QA rollback test: true seven 24-hour days, idempotent request,
-- authenticated owner-only status, owner cancellation, deadline race gate.
-- Request RPC is GRANTED only inside this transaction, never to real clients.
BEGIN;
GRANT EXECUTE ON FUNCTION public.request_account_deletion() TO authenticated;
SELECT set_config('qa.owner',(SELECT user_id::text FROM public.space_members ORDER BY space_id,user_id LIMIT 1),true);
SELECT set_config('qa.peer',(SELECT user_id::text FROM public.space_members WHERE space_id=(SELECT space_id FROM public.space_members WHERE user_id::text=current_setting('qa.owner') LIMIT 1) AND user_id::text<>current_setting('qa.owner') LIMIT 1),true);
SELECT set_config('request.jwt.claim.sub',current_setting('qa.owner'),true);
SET LOCAL ROLE authenticated;
DO $qa$
DECLARE first_due timestamptz;retry_due timestamptz;new_due timestamptz;
 user_status jsonb;
BEGIN
 first_due:=public.request_account_deletion();
 IF first_due < now()+interval '7 days'-interval '1 minute'
   OR first_due > now()+interval '7 days'+interval '1 minute' THEN
  RAISE EXCEPTION 'Grace period not exactly seven days';END IF;
 user_status:=public.my_account_deletion_status();
 IF user_status->>'state'<>'pending' OR user_status->>'can_cancel'<>'true' THEN
  RAISE EXCEPTION 'New request not pending and cancellable';END IF;
 retry_due:=public.request_account_deletion();
 IF retry_due IS DISTINCT FROM first_due THEN
  RAISE EXCEPTION 'Repeated request shortened or extended the deadline';END IF;
 PERFORM public.cancel_account_deletion();
 user_status:=public.my_account_deletion_status();
 IF user_status->>'state'<>'cancelled' OR user_status->>'can_cancel'<>'false' THEN
  RAISE EXCEPTION 'Owner cannot cancel in grace period';END IF;
 new_due:=public.request_account_deletion();
 IF new_due < now()+interval '7 days'-interval '1 minute' THEN
  RAISE EXCEPTION 'New request after cancellation lacks full seven days';END IF;
 PERFORM set_config('request.jwt.claim.sub',current_setting('qa.peer'),true);
 user_status:=public.my_account_deletion_status();
 IF user_status->>'state'<>'none' THEN
  RAISE EXCEPTION 'Partner can read someone else deletion request';END IF;
 PERFORM set_config('request.jwt.claim.sub',current_setting('qa.owner'),true);
END $qa$;
RESET ROLE;
UPDATE public.account_deletion_requests SET purge_after=now()-interval '1 second'
 WHERE user_id=current_setting('qa.owner')::uuid;
SET LOCAL ROLE authenticated;
DO $qa$
DECLARE current_status jsonb;
BEGIN
 current_status:=public.my_account_deletion_status();
 IF current_status->>'state'<>'due' OR current_status->>'can_cancel'<>'false' THEN
  RAISE EXCEPTION 'Due request remains cancellable';END IF;
 BEGIN
  PERFORM public.cancel_account_deletion();
  RAISE EXCEPTION 'BUG: cancellation after seven-day deadline accepted';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM LIKE 'BUG:%' THEN RAISE;END IF;END;
END $qa$;
ROLLBACK;
SELECT 'PASS 7-day request, idempotency, cancel/restart, partner isolation and overdue cancellation denial; rollback and client request stays revoked' result;