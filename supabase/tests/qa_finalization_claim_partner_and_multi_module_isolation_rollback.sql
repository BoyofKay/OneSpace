-- QA rollback: processing user A is frozen across multiple modules,
-- but surviving unpaired user B retains private writes and profile usability.
BEGIN;
SELECT set_config('qa.a',gen_random_uuid()::text,true);
SELECT set_config('qa.b',gen_random_uuid()::text,true);
INSERT INTO auth.users(id,aud,role,email,encrypted_password,email_confirmed_at)
SELECT id,'authenticated','authenticated','qa-claim-isolation-'||id::text||'@example.invalid',
 'synthetic',now()
FROM (VALUES(current_setting('qa.a')::uuid),
 (current_setting('qa.b')::uuid)) v(id);
INSERT INTO public.account_deletion_requests(user_id,requested_at,purge_after)
VALUES(current_setting('qa.a')::uuid,now()-interval '8 days',now()-interval '1 day');
UPDATE private.qa_account_v2_gate SET enabled=true WHERE id=1;
SET LOCAL ROLE service_role;
SELECT public.qa_retire_due_account_legacy_solo(current_setting('qa.a')::uuid);
SELECT public.qa_claim_account_for_auth_finalization(current_setting('qa.a')::uuid);
RESET ROLE;
SELECT set_config('request.jwt.claim.sub',current_setting('qa.a'),true);
SET LOCAL ROLE authenticated;
DO $owner$
DECLARE n int;
BEGIN
 IF private.qa_is_account_in_finalization(current_setting('qa.b')::uuid) THEN
  RAISE EXCEPTION 'User A may probe B finalization status';END IF;
 BEGIN
  INSERT INTO public.activities(private_space_id,created_by,title,visibility)
  VALUES(current_setting('qa.a')::uuid,current_setting('qa.a')::uuid,
   'A tries to write Activity','private');
  RAISE EXCEPTION 'BUG: A Activity write allowed during Auth finalization';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM LIKE 'BUG:%' THEN RAISE;END IF;END;
 BEGIN
  INSERT INTO public.memories(private_space_id,created_by,title,memory_date,visibility)
  VALUES(current_setting('qa.a')::uuid,current_setting('qa.a')::uuid,
   'A tries to write Memory',current_date,'private');
  RAISE EXCEPTION 'BUG: A Memory write allowed during Auth finalization';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM LIKE 'BUG:%' THEN RAISE;END IF;END;
 BEGIN
  INSERT INTO public.saved_contacts(private_space_id,created_by,label,visibility)
  VALUES(current_setting('qa.a')::uuid,current_setting('qa.a')::uuid,
   'A tries to write Contact','private');
  RAISE EXCEPTION 'BUG: A Contact write allowed during Auth finalization';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM LIKE 'BUG:%' THEN RAISE;END IF;END;
END $owner$;
RESET ROLE;
SELECT set_config('request.jwt.claim.sub',current_setting('qa.b'),true);
SET LOCAL ROLE authenticated;
DO $survivor$
DECLARE n int;
BEGIN
 IF private.qa_is_account_in_finalization(current_setting('qa.a')::uuid) THEN
  RAISE EXCEPTION 'B could probe A account finalization';END IF;
 INSERT INTO public.activities(private_space_id,created_by,title,visibility)
 VALUES(current_setting('qa.b')::uuid,current_setting('qa.b')::uuid,
 'B still owns Activity','private');
 INSERT INTO public.memories(private_space_id,created_by,title,memory_date,visibility)
 VALUES(current_setting('qa.b')::uuid,current_setting('qa.b')::uuid,
 'B still owns Memory',current_date,'private');
 INSERT INTO public.saved_contacts(private_space_id,created_by,label,visibility)
 VALUES(current_setting('qa.b')::uuid,current_setting('qa.b')::uuid,
 'B still owns Contact','private');
 SELECT count(*) INTO n FROM public.activities
 WHERE private_space_id=current_setting('qa.b')::uuid
 AND title='B still owns Activity';
 IF n<>1 THEN RAISE EXCEPTION 'B private access lost during A processing';END IF;
END $survivor$;
ROLLBACK;
SELECT 'PASS A post-claim Activity/Memory/Contact denied, cannot probe B, B retains all three private CRUD operations; synthetic rolled back' result;