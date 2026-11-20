-- QA only, rollback. Verify service-role-only deletion leases; no real files.
BEGIN;
SELECT set_config('qa.retired_space',gen_random_uuid()::text,true);
INSERT INTO public.qa_shared_media_purge_queue(space_id,bucket_id,object_path)
VALUES(current_setting('qa.retired_space')::uuid,'onespace-note-images',
       '11111111-1111-4111-8111-111111111111/22222222-2222-4222-8222-222222222222/33333333-3333-4333-8333-333333333333.jpg');
SELECT set_config('qa.owner',(SELECT user_id::text FROM public.space_members LIMIT 1),true);
SELECT set_config('request.jwt.claim.sub',current_setting('qa.owner'),true);
SET LOCAL ROLE authenticated;
DO $auth$
BEGIN
 BEGIN
  PERFORM public.qa_claim_shared_media_purge(1);
  RAISE EXCEPTION 'BUG: normal user can claim purge files';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM LIKE 'BUG:%' THEN RAISE;END IF;END;
END $auth$;
RESET ROLE;
SET LOCAL ROLE service_role;
DO $worker$
DECLARE jobs jsonb; job jsonb; id uuid; ok boolean;n integer;
BEGIN
 jobs:=public.qa_claim_shared_media_purge(1);
 IF jsonb_array_length(jobs)<>1 THEN
  RAISE EXCEPTION 'Service did not lease retired-space media';END IF;
 job:=jobs->0; id:=(job->>'lease_id')::uuid;
 jobs:=public.qa_claim_shared_media_purge(1);
 IF jsonb_array_length(jobs)<>0 THEN
  RAISE EXCEPTION 'Same media leased concurrently';END IF;
 ok:=public.qa_ack_shared_media_purge(current_setting('qa.retired_space')::uuid,
  'onespace-note-images',
  '11111111-1111-4111-8111-111111111111/22222222-2222-4222-8222-222222222222/33333333-3333-4333-8333-333333333333.jpg',
  gen_random_uuid(),true);
 IF ok THEN RAISE EXCEPTION 'False lease acknowledgement accepted';END IF;
 ok:=public.qa_ack_shared_media_purge(current_setting('qa.retired_space')::uuid,
  'onespace-note-images',
  '11111111-1111-4111-8111-111111111111/22222222-2222-4222-8222-222222222222/33333333-3333-4333-8333-333333333333.jpg',
  id,false);
 IF NOT ok THEN RAISE EXCEPTION 'Unable to record failed attempt';END IF;
 jobs:=public.qa_claim_shared_media_purge(1);
 IF jsonb_array_length(jobs)<>1 OR (jobs->0->>'attempts')::int<>2 THEN
  RAISE EXCEPTION 'Failed purge did not requeue';END IF;
 id:=(jobs->0->>'lease_id')::uuid;
 ok:=public.qa_ack_shared_media_purge(current_setting('qa.retired_space')::uuid,
  'onespace-note-images',
  '11111111-1111-4111-8111-111111111111/22222222-2222-4222-8222-222222222222/333333333333.jpg',
  id,true);
 -- Use the correct full key below; a mismatched path must be rejected.
 IF ok THEN RAISE EXCEPTION 'Wrong path acknowledgement accepted';END IF;
 ok:=public.qa_ack_shared_media_purge(current_setting('qa.retired_space')::uuid,
  'onespace-note-images',
  '11111111-1111-4111-8111-111111111111/22222222-2222-4222-8222-222222222222/33333333-3333-4333-8333-333333333333.jpg',
  id,true);
 IF NOT ok THEN RAISE EXCEPTION 'Successful purge not recorded';END IF;
 jobs:=public.qa_claim_shared_media_purge(1);
 IF jsonb_array_length(jobs)<>0 THEN RAISE EXCEPTION 'Completed purge reappeared';END IF;
 SELECT count(*) INTO n FROM public.qa_shared_media_purge_queue
 WHERE space_id=current_setting('qa.retired_space')::uuid AND deleted_at IS NOT NULL
 AND attempts=2;
 IF n<>1 THEN RAISE EXCEPTION 'Queue attempt/completion audit mismatch';END IF;
END $worker$;
ROLLBACK;
SELECT 'PASS service-only retired-space media claim, no duplicate lease, failed retry, wrong token/path rejection and exactly once acknowledgement; rolled back' result;