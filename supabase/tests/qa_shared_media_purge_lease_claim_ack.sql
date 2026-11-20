-- QA only, rollback. Verify service-role-only deletion leases; no real files.
BEGIN;
SELECT set_config('qa.retired_space',(SELECT space_id::text FROM public.space_members
 GROUP BY space_id HAVING count(*)=2 ORDER BY space_id LIMIT 1),true);
SELECT set_config('qa.owner',(SELECT user_id::text FROM public.space_members
 WHERE space_id=current_setting('qa.retired_space')::uuid LIMIT 1),true);
SELECT set_config('request.jwt.claim.sub',current_setting('qa.owner'),true);
DO $fixture$
DECLARE note_id uuid; p text; me uuid:=current_setting('qa.owner')::uuid;
BEGIN
 INSERT INTO public.notes(space_id,created_by,title,visibility)
 VALUES(current_setting('qa.retired_space')::uuid,me,'QA lease fixture','shared')
 RETURNING id INTO note_id;
 p:=note_id::text||'/'||me::text||'/'||gen_random_uuid()::text||'.jpg';
 INSERT INTO storage.objects(bucket_id,name,owner_id)
 VALUES('onespace-note-images',p,me::text);
 INSERT INTO public.note_images(note_id,created_by,object_path,storage_bucket_id)
 VALUES(note_id,me,p,'onespace-note-images');
 INSERT INTO public.qa_shared_media_purge_queue(space_id,bucket_id,object_path)
 VALUES(current_setting('qa.retired_space')::uuid,'onespace-note-images',p);
 PERFORM set_config('qa.object_path',p,true);
END $fixture$;
-- Deleting a space invalidates its existing membership, but not its queue.
DELETE FROM public.spaces WHERE id=current_setting('qa.retired_space')::uuid;
-- Simulate a Storage file being transferred after the pair is retired:
-- the worker must refuse to claim it even if the old queue was valid.
UPDATE storage.objects SET owner_id='ffffffff-ffff-4fff-8fff-ffffffffffff'
WHERE bucket_id='onespace-note-images' AND name=current_setting('qa.object_path');
SET LOCAL ROLE service_role;
DO $changed_owner$
DECLARE leased jsonb;
BEGIN
 leased:=public.qa_claim_shared_media_purge(1);
 IF jsonb_array_length(leased)<>0 THEN
  RAISE EXCEPTION 'BUG: worker claimed a Storage object with changed uploader';
 END IF;
END $changed_owner$;
RESET ROLE;
UPDATE storage.objects SET owner_id=current_setting('qa.owner')
WHERE bucket_id='onespace-note-images' AND name=current_setting('qa.object_path');
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
  current_setting('qa.object_path'),
  gen_random_uuid(),true);
 IF ok THEN RAISE EXCEPTION 'False lease acknowledgement accepted';END IF;
 ok:=public.qa_ack_shared_media_purge(current_setting('qa.retired_space')::uuid,
  'onespace-note-images',
  current_setting('qa.object_path'),
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
  current_setting('qa.object_path'),
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