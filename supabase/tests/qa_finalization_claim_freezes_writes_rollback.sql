-- QA rollback: due account can be claimed exactly once; claim is sticky
-- across RPC transactions. All authenticated data writes, cancellation and
-- creation of another relationship are denied; private data stays intact.
BEGIN;
SELECT set_config('qa.owner',gen_random_uuid()::text,true);
INSERT INTO auth.users(id,aud,role,email,encrypted_password,email_confirmed_at)
VALUES(current_setting('qa.owner')::uuid,'authenticated','authenticated',
 'qa-claim-'||current_setting('qa.owner')||'@example.invalid','synthetic',now());
INSERT INTO public.notes(private_space_id,created_by,title,visibility)
VALUES(current_setting('qa.owner')::uuid,current_setting('qa.owner')::uuid,
 'Preserve pending-Auth finalization note','private');
INSERT INTO public.account_deletion_requests(user_id,requested_at,purge_after)
VALUES(current_setting('qa.owner')::uuid,now()-interval '8 days',now()-interval '1 day');
SELECT set_config('request.jwt.claim.sub',current_setting('qa.owner'),true);
SET LOCAL ROLE authenticated;
DO $deny_client_claim$
BEGIN
 BEGIN
  PERFORM public.qa_claim_account_for_auth_finalization(current_setting('qa.owner')::uuid);
  RAISE EXCEPTION 'BUG: app client claimed Auth deletion';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM LIKE 'BUG:%' THEN RAISE;END IF;END;
END $deny_client_claim$;
RESET ROLE;
SET LOCAL ROLE service_role;
DO $deny_gate$
BEGIN
 BEGIN
  PERFORM public.qa_claim_account_for_auth_finalization(current_setting('qa.owner')::uuid);
  RAISE EXCEPTION 'BUG: account claimed behind closed gate';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM LIKE 'BUG:%' THEN RAISE;END IF;END;
END $deny_gate$;
RESET ROLE;
UPDATE private.qa_account_v2_gate SET enabled=true WHERE id=1;
SET LOCAL ROLE service_role;
DO $claim$
DECLARE c jsonb;
BEGIN
 PERFORM public.qa_retire_due_account_legacy_solo(current_setting('qa.owner')::uuid);
 c:=public.qa_claim_account_for_auth_finalization(current_setting('qa.owner')::uuid);
 IF c->>'claimed'<>'true' OR (c->'readiness'->>'ready_for_auth_delete')<>'true'
    OR c->>'claim_id' IS NULL THEN
  RAISE EXCEPTION 'Account finalization claim is incomplete: %',c;END IF;
 BEGIN
  PERFORM public.qa_claim_account_for_auth_finalization(current_setting('qa.owner')::uuid);
  RAISE EXCEPTION 'BUG: second concurrent Auth claim allowed';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM LIKE 'BUG:%' THEN RAISE;END IF;END;
END $claim$;
RESET ROLE;
SET LOCAL ROLE authenticated;
DO $freeze$
DECLARE blocked boolean;
BEGIN
 IF NOT private.qa_is_account_in_finalization(current_setting('qa.owner')::uuid)
 THEN RAISE EXCEPTION 'Claim invisible to user security fence';END IF;
 blocked:=false;
 BEGIN
  INSERT INTO public.notes(private_space_id,created_by,title,visibility)
  VALUES(current_setting('qa.owner')::uuid,current_setting('qa.owner')::uuid,
   'Cannot create after claim','private');
 EXCEPTION WHEN OTHERS THEN blocked:=SQLERRM LIKE '%finalization has started%';END;
 IF NOT blocked THEN RAISE EXCEPTION 'BUG: post-claim private write accepted';END IF;
 blocked:=false;
 BEGIN
  UPDATE public.notes SET title='No updates after claim'
  WHERE private_space_id=current_setting('qa.owner')::uuid;
 EXCEPTION WHEN OTHERS THEN blocked:=SQLERRM LIKE '%finalization has started%';END;
 IF NOT blocked THEN RAISE EXCEPTION 'BUG: post-claim update accepted';END IF;
 blocked:=false;
 BEGIN
  PERFORM public.cancel_account_deletion();
 EXCEPTION WHEN OTHERS THEN blocked:=true;END;
 IF NOT blocked THEN RAISE EXCEPTION 'BUG: processing account cancelled';END IF;
 blocked:=false;
 BEGIN
  INSERT INTO public.spaces(created_by,name)
  VALUES(current_setting('qa.owner')::uuid,'Illegal new pair while finalizing');
 EXCEPTION WHEN OTHERS THEN blocked:=true;END;
 IF NOT blocked THEN RAISE EXCEPTION 'BUG: processing account created couple';END IF;
END $freeze$;
RESET ROLE;
DO $snapshot$
DECLARE n int;
BEGIN
 SELECT count(*) INTO n FROM public.notes
 WHERE private_space_id=current_setting('qa.owner')::uuid;
 IF n<>1 THEN RAISE EXCEPTION 'Claim mutated protected personal Notes';END IF;
END $snapshot$;
ROLLBACK;
SELECT 'PASS atomic claim is gate-off by default, service-only, single-use; active claim freezes client Notes, cancel and pairing; fully rolled back' result;