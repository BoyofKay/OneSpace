-- QA rollback: public relationship facade is auth-only, exact-action,
-- exact-actor and exact-warning; gate stays OFF outside this transaction.
BEGIN;
SELECT set_config('qa.owner',gen_random_uuid()::text,true);
SELECT set_config('qa.peer',gen_random_uuid()::text,true);
SELECT set_config('qa.outsider',gen_random_uuid()::text,true);
INSERT INTO auth.users(id,aud,role,email,encrypted_password,email_confirmed_at)
SELECT id,'authenticated','authenticated',
 'qa-end-api-'||id::text||'@example.invalid','synthetic',now()
FROM (VALUES(current_setting('qa.owner')::uuid),
 (current_setting('qa.peer')::uuid),(current_setting('qa.outsider')::uuid)) v(id);
INSERT INTO public.spaces(created_by,name)
VALUES(current_setting('qa.owner')::uuid,'QA guarded couple facade');
SELECT set_config('qa.sp',(SELECT id::text FROM public.spaces
 WHERE created_by=current_setting('qa.owner')::uuid
  AND name='QA guarded couple facade'),true);
INSERT INTO public.space_members(space_id,user_id)
VALUES(current_setting('qa.sp')::uuid,current_setting('qa.owner')::uuid),
      (current_setting('qa.sp')::uuid,current_setting('qa.peer')::uuid);
SELECT set_config('request.jwt.claim.sub',current_setting('qa.owner'),true);
SET LOCAL ROLE authenticated;
INSERT INTO public.notes(private_space_id,created_by,title,visibility)
VALUES(current_setting('qa.owner')::uuid,current_setting('qa.owner')::uuid,
 'Owner secret survives','private');
INSERT INTO public.notes(space_id,created_by,title,visibility)
VALUES(current_setting('qa.sp')::uuid,current_setting('qa.owner')::uuid,
 'Shared must disappear','shared');
RESET ROLE;
-- Separation is now ON in QA; switch it off inside this rolled-back test only.
UPDATE private.qa_relationship_v2_gate SET enabled=false WHERE id=1;
SET LOCAL ROLE authenticated;
DO $gate$
BEGIN
 BEGIN
  PERFORM public.qa_end_current_relationship(current_setting('qa.sp')::uuid,
    'remove_partner','DELETE SHARED CONTENT');
  RAISE EXCEPTION 'BUG: public facade bypassed disabled lifecycle gate';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM LIKE 'BUG:%' THEN RAISE;END IF;END;
END $gate$;
RESET ROLE;
UPDATE private.qa_relationship_v2_gate SET enabled=true WHERE id=1;
SELECT set_config('request.jwt.claim.sub',current_setting('qa.outsider'),true);
SET LOCAL ROLE authenticated;
DO $outsider$
BEGIN
 BEGIN
  PERFORM public.qa_end_current_relationship(current_setting('qa.sp')::uuid,
    'remove_partner','DELETE SHARED CONTENT');
  RAISE EXCEPTION 'BUG: outsider deleted other couple';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM LIKE 'BUG:%' THEN RAISE;END IF;END;
END $outsider$;
RESET ROLE;
SELECT set_config('request.jwt.claim.sub',current_setting('qa.peer'),true);
SET LOCAL ROLE authenticated;
DO $guest$
BEGIN
 BEGIN
  PERFORM public.qa_end_current_relationship(current_setting('qa.sp')::uuid,
    'remove_partner','DELETE SHARED CONTENT');
  RAISE EXCEPTION 'BUG: guest removed owner';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM LIKE 'BUG:%' THEN RAISE;END IF;END;
END $guest$;
RESET ROLE;
SELECT set_config('request.jwt.claim.sub',current_setting('qa.owner'),true);
SET LOCAL ROLE authenticated;
DO $owner$
DECLARE r jsonb;n int;
BEGIN
 BEGIN
  PERFORM public.qa_end_current_relationship(current_setting('qa.sp')::uuid,
    'remove_partner','DELETE');
  RAISE EXCEPTION 'BUG: skipped explicit shared content warning';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM LIKE 'BUG:%' THEN RAISE;END IF;END;
 r:=public.qa_end_current_relationship(current_setting('qa.sp')::uuid,
    'remove_partner','DELETE SHARED CONTENT');
 IF r->>'status'<>'shared_db_removed_storage_purge_pending' THEN
  RAISE EXCEPTION 'Authorized shared deletion transaction failed: %',r;END IF;
 SELECT count(*) INTO n FROM public.notes
 WHERE private_space_id=current_setting('qa.owner')::uuid;
 IF n<>1 THEN RAISE EXCEPTION 'Private owner Note deleted';END IF;
 SELECT count(*) INTO n FROM public.notes
 WHERE space_id=current_setting('qa.sp')::uuid;
 IF n<>0 THEN RAISE EXCEPTION 'Shared Note survived';END IF;
END $owner$;
ROLLBACK;
SELECT 'PASS authenticated couple facade fails closed, rejects outsider/guest/bad warning and preserves account private records after authorized deletion; rollback' result;
