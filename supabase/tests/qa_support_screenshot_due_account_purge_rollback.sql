-- QA rollback: a support screenshot owned by an account due for deletion
-- must not block finalization permanently; service can inventory/lease it.
-- Actual byte deletion is NOT performed by this SQL test.
BEGIN;
SELECT set_config('qa.user',gen_random_uuid()::text,true);
INSERT INTO auth.users(id,aud,role,email,encrypted_password,email_confirmed_at)
VALUES(current_setting('qa.user')::uuid,'authenticated','authenticated',
 'qa-support-cleanup-'||current_setting('qa.user')||'@example.invalid','synthetic',now());
SELECT set_config('qa.path',current_setting('qa.user')||'/1763638800000.jpg',true);
INSERT INTO storage.objects(bucket_id,name,owner_id)
VALUES('onespace-support',current_setting('qa.path'),current_setting('qa.user'));
INSERT INTO public.account_deletion_requests(user_id,requested_at,purge_after)
VALUES(current_setting('qa.user')::uuid,now()-interval '8 days',now()-interval '1 day');
SET LOCAL ROLE authenticated;
DO $deny$
BEGIN
 BEGIN
  PERFORM public.qa_claim_due_account_private_media(1);
  RAISE EXCEPTION 'BUG: app user called owner screenshot purge worker';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM LIKE 'BUG:%' THEN RAISE;END IF;END;
END $deny$;
RESET ROLE;
UPDATE private.qa_account_v2_gate SET enabled=true WHERE id=1;
SET LOCAL ROLE service_role;
DO $service$
DECLARE info jsonb; jobs jsonb;pass boolean;ready jsonb;
BEGIN
 PERFORM public.qa_retire_due_account_legacy_solo(current_setting('qa.user')::uuid);
 info:=private.qa_inventory_due_private_media(current_setting('qa.user')::uuid);
 IF (info->>'files_queued')::integer<>1 THEN
  RAISE EXCEPTION 'Owner screenshot was omitted from account media inventory';END IF;
 jobs:=public.qa_claim_due_account_private_media(3);
 IF jsonb_array_length(jobs)<>1 OR jobs->0->>'bucket_id'<>'onespace-support'
  OR jobs->0->>'object_path'<>current_setting('qa.path') THEN
  RAISE EXCEPTION 'Support screenshot lease mismatched original owner/path';END IF;
 pass:=public.qa_ack_due_account_private_media(
  current_setting('qa.user')::uuid,'onespace-support',current_setting('qa.path'),
  (jobs->0->>'lease_id')::uuid,true);
 IF NOT pass THEN RAISE EXCEPTION 'Support screenshot acknowledgement failed';END IF;
 ready:=public.qa_account_final_deletion_readiness(current_setting('qa.user')::uuid);
 IF ready->>'ready_for_auth_delete'<>'false'
  OR (ready->>'remaining_storage_objects_owned')::integer<>1 THEN
  RAISE EXCEPTION 'Marked-complete job bypassed real physical file existence';END IF;
END $service$;
ROLLBACK;
SELECT 'PASS due owner support image captured, leased and guarded by actual Storage bytes; everything rolled back' result;