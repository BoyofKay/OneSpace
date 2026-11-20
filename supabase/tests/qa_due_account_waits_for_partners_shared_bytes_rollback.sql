-- QA rollback: A deletes account, but the old couple's shared image was
-- uploaded by B. Finalizer must await B's shared bytes, and scrub their
-- completed shared job only AFTER physical deletion. No real files touched.
BEGIN;
SELECT set_config('qa.a',gen_random_uuid()::text,true);
SELECT set_config('qa.b',gen_random_uuid()::text,true);
INSERT INTO auth.users(id,aud,role,email,encrypted_password,email_confirmed_at)
SELECT u,'authenticated','authenticated',
 'qa-cross-uploader-'||u::text||'@example.invalid','synthetic',now()
FROM (VALUES(current_setting('qa.a')::uuid),
 (current_setting('qa.b')::uuid)) v(u);
INSERT INTO public.spaces(created_by,name)
VALUES(current_setting('qa.a')::uuid,'QA due shared-media A+B');
SELECT set_config('qa.sp',(SELECT id::text FROM public.spaces
 WHERE created_by=current_setting('qa.a')::uuid
  AND name='QA due shared-media A+B'),true);
INSERT INTO public.space_members(space_id,user_id)
VALUES(current_setting('qa.sp')::uuid,current_setting('qa.a')::uuid),
      (current_setting('qa.sp')::uuid,current_setting('qa.b')::uuid);
SELECT set_config('request.jwt.claim.sub',current_setting('qa.b'),true);
SET LOCAL ROLE authenticated;
INSERT INTO public.notes(space_id,created_by,title,visibility)
VALUES(current_setting('qa.sp')::uuid,current_setting('qa.b')::uuid,
 'Shared B-owned photograph parent','shared');
INSERT INTO public.notes(private_space_id,created_by,title,visibility)
VALUES(current_setting('qa.b')::uuid,current_setting('qa.b')::uuid,
 'B private survivor note','private');
RESET ROLE;
SELECT set_config('qa.note',(SELECT id::text FROM public.notes
 WHERE title='Shared B-owned photograph parent'
  AND space_id=current_setting('qa.sp')::uuid),true);
SELECT set_config('qa.path',current_setting('qa.note')||'/'||
 current_setting('qa.b')||'/'||gen_random_uuid()::text||'.jpg',true);
INSERT INTO storage.objects(bucket_id,name,owner_id)
VALUES('onespace-note-images',current_setting('qa.path'),current_setting('qa.b'));
INSERT INTO public.note_images(note_id,created_by,object_path,storage_bucket_id)
VALUES(current_setting('qa.note')::uuid,current_setting('qa.b')::uuid,
 current_setting('qa.path'),'onespace-note-images');
INSERT INTO public.account_deletion_requests(user_id,requested_at,purge_after)
VALUES(current_setting('qa.a')::uuid,now()-interval '8 days',now()-interval '1 day');
UPDATE private.qa_relationship_v2_gate SET enabled=true WHERE id=1;
UPDATE private.qa_account_v2_gate SET enabled=true WHERE id=1;
SET LOCAL ROLE service_role;
DO $initial$
DECLARE v jsonb; request_space uuid;
BEGIN
 PERFORM public.qa_due_account_close_current_relationship(current_setting('qa.a')::uuid);
 PERFORM public.qa_retire_due_account_legacy_solo(current_setting('qa.a')::uuid);
 SELECT closing_space_id INTO request_space
 FROM public.account_deletion_requests
 WHERE user_id=current_setting('qa.a')::uuid;
 IF request_space IS DISTINCT FROM current_setting('qa.sp')::uuid THEN
  RAISE EXCEPTION 'Account request lost identity of erased relationship';
 END IF;
 v:=public.qa_account_final_deletion_readiness(current_setting('qa.a')::uuid);
 IF v->>'ready_for_auth_delete'<>'false'
  OR (v->>'unfinished_shared_file_purges')::integer<>1
  OR (v->>'remaining_shared_storage_objects')::integer<>1
  OR (v->>'remaining_storage_objects_owned')::integer<>0 THEN
  RAISE EXCEPTION 'BUG: A can be Auth deleted while B shared file remains: %',v;
 END IF;
 -- A service acknowledgement is only metadata: it cannot prove bytes gone.
 UPDATE public.qa_shared_media_purge_queue
 SET deleted_at=now()
 WHERE space_id=request_space AND object_path=current_setting('qa.path');
 v:=public.qa_account_final_deletion_readiness(current_setting('qa.a')::uuid);
 IF v->>'ready_for_auth_delete'<>'false'
  OR (v->>'unfinished_shared_file_purges')::integer<>0
  OR (v->>'remaining_shared_storage_objects')::integer<>1 THEN
  RAISE EXCEPTION 'BUG: completed queue flag bypassed actual shared bytes: %',v;
 END IF;
END $initial$;
RESET ROLE;
-- ONLY within this rollback fixture, emulate *Storage metadata removal*;
-- production worker MUST remove actual bytes using Storage API.
DELETE FROM storage.objects WHERE bucket_id='onespace-note-images'
 AND name=current_setting('qa.path');
SET LOCAL ROLE service_role;
DO $cleared$
DECLARE v jsonb; scrub jsonb;n integer;
BEGIN
 v:=public.qa_account_final_deletion_readiness(current_setting('qa.a')::uuid);
 IF v->>'ready_for_auth_delete'<>'true'
  OR (v->>'remaining_shared_storage_objects')::integer<>0 THEN
  RAISE EXCEPTION 'Fully purged synthetic couple still blocked: %',v;
 END IF;
 scrub:=public.qa_scrub_completed_account_media_jobs(current_setting('qa.a')::uuid);
 IF (scrub->>'completed_shared_jobs_scrubbed')::integer<>1 THEN
  RAISE EXCEPTION 'Partner-uploaded completed shared purge record was retained';
 END IF;
 SELECT count(*) INTO n FROM public.notes
 WHERE private_space_id=current_setting('qa.b')::uuid
 AND title='B private survivor note';
 IF n<>1 THEN RAISE EXCEPTION 'Survivor B lost personal content';END IF;
END $cleared$;
ROLLBACK;
SELECT 'PASS A Auth deletion blocked until B uploaded old shared bytes gone; completion flag alone insufficient, completed metadata scrubbed, B private survives; rollback' result;
