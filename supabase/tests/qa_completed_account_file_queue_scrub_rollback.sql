-- QA rollback: finished media queues must not preserve a deleted user's
-- identifying paths; uncompleted tasks are never erased to hide failed work.
BEGIN;
SELECT set_config('qa.fake',gen_random_uuid()::text,true);
INSERT INTO auth.users(id,aud,role,email,encrypted_password,email_confirmed_at)
VALUES(current_setting('qa.fake')::uuid,'authenticated','authenticated',
 'qa-scrub-'||current_setting('qa.fake')||'@example.invalid','fake',now());
INSERT INTO public.account_deletion_requests(user_id,requested_at,purge_after)
VALUES(current_setting('qa.fake')::uuid,now()-interval '8 days',now()-interval '1 day');
INSERT INTO public.qa_account_private_media_purge_queue(
 owner_id,bucket_id,object_path,deleted_at)
VALUES(current_setting('qa.fake')::uuid,'onespace-private-activity-media',
 gen_random_uuid()::text||'/'||current_setting('qa.fake')||'/'||
 gen_random_uuid()::text||'.jpg',now());
SELECT set_config('request.jwt.claim.sub',current_setting('qa.fake'),true);
SET LOCAL ROLE authenticated;
DO $user$
BEGIN
 BEGIN
  PERFORM public.qa_scrub_completed_account_media_jobs(current_setting('qa.fake')::uuid);
  RAISE EXCEPTION 'BUG: authenticated caller erased account purge history';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM LIKE 'BUG:%' THEN RAISE; END IF;END;
END $user$;
RESET ROLE;
UPDATE private.qa_account_v2_gate SET enabled=true WHERE id=1;
SET LOCAL ROLE service_role;
SELECT public.qa_retire_due_account_legacy_solo(current_setting('qa.fake')::uuid);
DO $scrub$
DECLARE result jsonb;count_left integer;not_allowed boolean:=false;
BEGIN
 result:=public.qa_scrub_completed_account_media_jobs(current_setting('qa.fake')::uuid);
 IF (result->>'completed_private_jobs_scrubbed')::integer<>1 THEN
  RAISE EXCEPTION 'Completed personal path record was not scrubbed';END IF;
 SELECT count(*) INTO count_left FROM public.qa_account_private_media_purge_queue
 WHERE owner_id=current_setting('qa.fake')::uuid;
 IF count_left<>0 THEN RAISE EXCEPTION 'Completed file path identity retained';END IF;
 INSERT INTO public.qa_account_private_media_purge_queue(owner_id,bucket_id,object_path)
 VALUES(current_setting('qa.fake')::uuid,'onespace-private-note-images',
 gen_random_uuid()::text||'/'||current_setting('qa.fake')||'/'||
 gen_random_uuid()::text||'.jpg');
 BEGIN
  PERFORM public.qa_scrub_completed_account_media_jobs(current_setting('qa.fake')::uuid);
 EXCEPTION WHEN OTHERS THEN not_allowed:=true;
 END;
 IF NOT not_allowed THEN RAISE EXCEPTION 'Unfinished file purge wrongly scrubbed';END IF;
 SELECT count(*) INTO count_left FROM public.qa_account_private_media_purge_queue
 WHERE owner_id=current_setting('qa.fake')::uuid AND deleted_at IS NULL;
 IF count_left<>1 THEN RAISE EXCEPTION 'Pending deletion job was removed';END IF;
END $scrub$;
ROLLBACK;
SELECT 'PASS service-only scrub erases completed file-path metadata only after final readiness; preserves unfinished work; rolled back' result;