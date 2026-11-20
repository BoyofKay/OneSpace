-- QA ROLLBACK: service lease ownership, full grace, no pairing,
-- file re-ownership veto, failed retry, stale token rejection, success exactly once.
BEGIN;
SELECT set_config('qa.owner',(SELECT m.user_id::text FROM public.space_members m
 WHERE EXISTS(SELECT 1 FROM public.user_private_spaces p WHERE p.owner_id=m.user_id)
 ORDER BY m.user_id LIMIT 1),true);
SELECT set_config('qa.other',(SELECT owner_id::text FROM public.user_private_spaces
 WHERE owner_id::text<>current_setting('qa.owner') ORDER BY owner_id LIMIT 1),true);
SELECT set_config('qa.path',gen_random_uuid()::text||'/'||
  current_setting('qa.owner')||'/'||gen_random_uuid()::text||'.jpg',true);
INSERT INTO public.account_deletion_requests(user_id,requested_at,purge_after)
VALUES(current_setting('qa.owner')::uuid,now()-interval '8 days',now()-interval '1 day');
INSERT INTO storage.objects(bucket_id,name,owner_id)
VALUES('onespace-private-activity-media',current_setting('qa.path'),
 current_setting('qa.owner'));
INSERT INTO public.qa_account_private_media_purge_queue(owner_id,bucket_id,object_path)
VALUES(current_setting('qa.owner')::uuid,'onespace-private-activity-media',
 current_setting('qa.path'));
SELECT set_config('request.jwt.claim.sub',current_setting('qa.owner'),true);
SET LOCAL ROLE authenticated;
DO $app$
BEGIN
 BEGIN
  PERFORM public.qa_claim_due_account_private_media(1);
  RAISE EXCEPTION 'BUG: user can claim private media purge';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM LIKE 'BUG:%' THEN RAISE; END IF;END;
END $app$;
RESET ROLE;
SET LOCAL ROLE service_role;
DO $gate$
BEGIN
 BEGIN
  PERFORM public.qa_claim_due_account_private_media(1);
  RAISE EXCEPTION 'BUG: service bypassed closed account purge gate';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM LIKE 'BUG:%' THEN RAISE; END IF;END;
END $gate$;
RESET ROLE;
UPDATE private.qa_account_v2_gate SET enabled=true WHERE id=1;
SET LOCAL ROLE service_role;
DO $pair$
DECLARE jobs jsonb;
BEGIN
 jobs:=public.qa_claim_due_account_private_media(1);
 IF jsonb_array_length(jobs)<>0 THEN
   RAISE EXCEPTION 'BUG: active relationship did not block media purge';
 END IF;
END $pair$;
RESET ROLE;
-- Change only transaction-local QA records. Rollback restores their creator
-- and membership; no actual relationship closure is committed.
UPDATE public.spaces s SET created_by=current_setting('qa.other')::uuid
 WHERE s.created_by=current_setting('qa.owner')::uuid;
DELETE FROM public.space_members m WHERE m.user_id=current_setting('qa.owner')::uuid;
SET LOCAL ROLE service_role;
DO $worker$
DECLARE jobs jsonb;lease uuid;ok boolean; n integer;
BEGIN
 -- Reassigned Storage ownership must stop claims.
 UPDATE storage.objects SET owner_id=current_setting('qa.other')
 WHERE bucket_id='onespace-private-activity-media'
  AND name=current_setting('qa.path');
 jobs:=public.qa_claim_due_account_private_media(1);
 IF jsonb_array_length(jobs)<>0 THEN
  RAISE EXCEPTION 'BUG: service claimed file now owned by another account';
 END IF;
 UPDATE storage.objects SET owner_id=current_setting('qa.owner')
 WHERE bucket_id='onespace-private-activity-media'
  AND name=current_setting('qa.path');
 jobs:=public.qa_claim_due_account_private_media(1);
 IF jsonb_array_length(jobs)<>1 THEN
  RAISE EXCEPTION 'Eligible due-account media not leased';
 END IF;
 lease:=(jobs->0->>'lease_id')::uuid;
 jobs:=public.qa_claim_due_account_private_media(1);
 IF jsonb_array_length(jobs)<>0 THEN
  RAISE EXCEPTION 'Duplicate active lease accepted';
 END IF;
 ok:=public.qa_ack_due_account_private_media(
  current_setting('qa.owner')::uuid,'onespace-private-activity-media',
  current_setting('qa.path'),gen_random_uuid(),true);
 IF ok THEN RAISE EXCEPTION 'Wrong lease token accepted';END IF;
 ok:=public.qa_ack_due_account_private_media(
  current_setting('qa.owner')::uuid,'onespace-private-activity-media',
  current_setting('qa.path'),lease,false);
 IF NOT ok THEN RAISE EXCEPTION 'Failed file deletion not acknowledged';END IF;
 jobs:=public.qa_claim_due_account_private_media(1);
 IF jsonb_array_length(jobs)<>1 OR (jobs->0->>'attempts')::integer<>2 THEN
  RAISE EXCEPTION 'Failed file did not requeue for second attempt';END IF;
 lease:=(jobs->0->>'lease_id')::uuid;
 ok:=public.qa_ack_due_account_private_media(
  current_setting('qa.owner')::uuid,'onespace-private-activity-media',
  current_setting('qa.path'),lease,true);
 IF NOT ok THEN RAISE EXCEPTION 'Successful service deletion could not be acknowledged';END IF;
 jobs:=public.qa_claim_due_account_private_media(1);
 IF jsonb_array_length(jobs)<>0 THEN RAISE EXCEPTION 'Completed file was requeued';END IF;
 SELECT count(*) INTO n FROM public.qa_account_private_media_purge_queue
 WHERE owner_id=current_setting('qa.owner')::uuid AND deleted_at IS NOT NULL AND attempts=2;
 IF n<>1 THEN RAISE EXCEPTION 'Completion/attempt audit incorrect';END IF;
END $worker$;
ROLLBACK;
SELECT 'PASS service-only account purge leases block paired users and re-owned files, reject stale lease, retry failures and acknowledge once; rollback restored all rows' result;