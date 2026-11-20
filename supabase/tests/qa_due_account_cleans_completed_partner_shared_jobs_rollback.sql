-- QA rollback: B uploads/attaches shared file reference but the physical
-- file is ALREADY absent (as it would be after successful Storage API purge).
-- A's due-account Auth readiness must allow finalization and scrub the
-- completed B-uploaded queue record before removing A. No actual bytes used.
BEGIN;
SELECT set_config('qa.a',gen_random_uuid()::text,true);
SELECT set_config('qa.b',gen_random_uuid()::text,true);
INSERT INTO auth.users(id,aud,role,email,encrypted_password,email_confirmed_at)
SELECT u,'authenticated','authenticated',
 'qa-scrub-other-'||u::text||'@example.invalid','synthetic',now()
FROM (VALUES(current_setting('qa.a')::uuid),
 (current_setting('qa.b')::uuid)) v(u);
INSERT INTO public.spaces(created_by,name)
VALUES(current_setting('qa.a')::uuid,'QA cleaned B uploader');
SELECT set_config('qa.sp',(SELECT id::text FROM public.spaces
 WHERE created_by=current_setting('qa.a')::uuid AND name='QA cleaned B uploader'),true);
INSERT INTO public.space_members(space_id,user_id)
VALUES(current_setting('qa.sp')::uuid,current_setting('qa.a')::uuid),
      (current_setting('qa.sp')::uuid,current_setting('qa.b')::uuid);
SELECT set_config('request.jwt.claim.sub',current_setting('qa.b'),true);
SET LOCAL ROLE authenticated;
INSERT INTO public.notes(space_id,created_by,title,visibility)
VALUES(current_setting('qa.sp')::uuid,current_setting('qa.b')::uuid,
 'Partner B media parent, physical object absent','shared');
INSERT INTO public.notes(private_space_id,created_by,title,visibility)
VALUES(current_setting('qa.b')::uuid,current_setting('qa.b')::uuid,
 'B private note stays','private');
RESET ROLE;
SELECT set_config('qa.note',(SELECT id::text FROM public.notes
 WHERE title='Partner B media parent, physical object absent'),true);
SELECT set_config('qa.path',current_setting('qa.note')||'/'||
 current_setting('qa.b')||'/'||gen_random_uuid()::text||'.jpg',true);
-- An absent Storage object is intentionally valid: the cleanup worker
-- may have already removed its bytes but not yet cleared the metadata row.
INSERT INTO public.note_images(note_id,created_by,object_path,storage_bucket_id)
VALUES(current_setting('qa.note')::uuid,current_setting('qa.b')::uuid,
 current_setting('qa.path'),'onespace-note-images');
INSERT INTO public.account_deletion_requests(user_id,requested_at,purge_after)
VALUES(current_setting('qa.a')::uuid,now()-interval '8 days',now()-interval '1 day');
UPDATE private.qa_relationship_v2_gate SET enabled=true WHERE id=1;
UPDATE private.qa_account_v2_gate SET enabled=true WHERE id=1;
SET LOCAL ROLE service_role;
DO $assert$
DECLARE v jsonb; s jsonb;n integer;
BEGIN
 PERFORM public.qa_due_account_close_current_relationship(current_setting('qa.a')::uuid);
 PERFORM public.qa_retire_due_account_legacy_solo(current_setting('qa.a')::uuid);
 v:=public.qa_account_final_deletion_readiness(current_setting('qa.a')::uuid);
 IF v->>'ready_for_auth_delete'<>'false'
  OR (v->>'unfinished_shared_file_purges')::integer<>1
  OR (v->>'remaining_shared_storage_objects')::integer<>0 THEN
  RAISE EXCEPTION 'Unfinished B-owned queue not blocked as expected: %',v;
 END IF;
 UPDATE public.qa_shared_media_purge_queue SET deleted_at=now()
 WHERE space_id=current_setting('qa.sp')::uuid
  AND object_path=current_setting('qa.path');
 v:=public.qa_account_final_deletion_readiness(current_setting('qa.a')::uuid);
 IF v->>'ready_for_auth_delete'<>'true' THEN
  RAISE EXCEPTION 'Completed B-owned missing-byte job incorrectly blocks A: %',v;
 END IF;
 s:=public.qa_scrub_completed_account_media_jobs(current_setting('qa.a')::uuid);
 IF (s->>'completed_shared_jobs_scrubbed')::integer<>1 THEN
  RAISE EXCEPTION 'Failed to erase completed B uploader metadata when A deletes';
 END IF;
 SELECT count(*) INTO n FROM public.notes
 WHERE private_space_id=current_setting('qa.b')::uuid
  AND title='B private note stays';
 IF n<>1 THEN RAISE EXCEPTION 'B personal content lost';END IF;
END $assert$;
ROLLBACK;
SELECT 'PASS no-storage completed B uploaded shared queue no longer blocks A Auth readiness; metadata scrubbed and B private survives; rollback' result;