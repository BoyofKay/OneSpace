-- QA ONLY: synthetic, NEVER existing real user. This tests the SQL FK
-- cascade path inside a rollback, NOT an actual Auth Admin API deletion.
BEGIN;
SELECT set_config('qa.synthetic',gen_random_uuid()::text,true);
SELECT set_config('qa.other',(SELECT owner_id::text FROM public.user_private_spaces
 ORDER BY owner_id LIMIT 1),true);
INSERT INTO auth.users(id,aud,role,email,encrypted_password,email_confirmed_at)
VALUES(current_setting('qa.synthetic')::uuid,'authenticated','authenticated',
 'qa-rollback-'||current_setting('qa.synthetic')||'@example.invalid',
 'not-a-real-password-hash',now());
DO $signup$
DECLARE p integer;s integer;
BEGIN
 SELECT count(*) INTO p FROM public.user_private_spaces
 WHERE owner_id=current_setting('qa.synthetic')::uuid;
 SELECT count(*) INTO s FROM public.spaces
 WHERE personal_owner=current_setting('qa.synthetic')::uuid;
 IF p<>1 OR s<>1 THEN
  RAISE EXCEPTION 'Expected synthetic sign-up to create one private namespace and old solo space';
 END IF;
END $signup$;
SELECT set_config('request.jwt.claim.sub',current_setting('qa.synthetic'),true);
SET LOCAL ROLE authenticated;
INSERT INTO public.notes(private_space_id,created_by,title,visibility)
VALUES(current_setting('qa.synthetic')::uuid,current_setting('qa.synthetic')::uuid,
 'Synthetic personal Note doomed only on account delete','private');
DO $deny$
BEGIN
 BEGIN
  PERFORM public.qa_retire_due_account_legacy_solo(current_setting('qa.synthetic')::uuid);
  RAISE EXCEPTION 'BUG: normal user can invoke service-only cleanup';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM LIKE 'BUG:%' THEN RAISE;END IF;END;
END $deny$;
RESET ROLE;
INSERT INTO public.account_deletion_requests(user_id,requested_at,purge_after)
VALUES(current_setting('qa.synthetic')::uuid,now()-interval '8 days',now()-interval '1 day');
UPDATE private.qa_account_v2_gate SET enabled=true WHERE id=1;
SET LOCAL ROLE service_role;
DO $ready$
DECLARE result jsonb;check_result jsonb;n integer;
BEGIN
 check_result:=public.qa_account_final_deletion_readiness(current_setting('qa.synthetic')::uuid);
 IF check_result->>'ready_for_auth_delete'<>'false'
  OR (check_result->>'remaining_created_spaces')::integer<>1 THEN
   RAISE EXCEPTION 'Auth deletion preflight failed to find legacy solo space';
 END IF;
 result:=public.qa_retire_due_account_legacy_solo(current_setting('qa.synthetic')::uuid);
 IF (result->>'retired_legacy_solo_spaces')::integer<>1 THEN
  RAISE EXCEPTION 'Failed to retire synthetic due-account legacy solo space';END IF;
 SELECT count(*) INTO n FROM public.user_private_spaces
 WHERE owner_id=current_setting('qa.synthetic')::uuid;
 IF n<>1 THEN RAISE EXCEPTION 'Solo retirement destroyed real private namespace';END IF;
 check_result:=public.qa_account_final_deletion_readiness(current_setting('qa.synthetic')::uuid);
 IF check_result->>'ready_for_auth_delete'<>'true' THEN
  RAISE EXCEPTION 'Clean synthetic due account failed the final deletion preflight: %',
  check_result;
 END IF;
END $ready$;
RESET ROLE;
-- Synthetic SQL delete verifies real FK cascades atomically within rollback.
-- Actual Auth Admin deleteUser remains UNIMPLEMENTED/UNDEPLOYED.
DELETE FROM auth.users WHERE id=current_setting('qa.synthetic')::uuid;
DO $cascade$
DECLARE n integer;
BEGIN
 SELECT count(*) INTO n FROM public.user_private_spaces
 WHERE owner_id=current_setting('qa.synthetic')::uuid;
 IF n<>0 THEN RAISE EXCEPTION 'Auth FK cascade failed for synthetic private namespace';END IF;
 SELECT count(*) INTO n FROM public.notes
 WHERE created_by=current_setting('qa.synthetic')::uuid;
 IF n<>0 THEN RAISE EXCEPTION 'Synthetic private Note survived account deletion';END IF;
 SELECT count(*) INTO n FROM public.user_private_spaces
 WHERE owner_id=current_setting('qa.other')::uuid;
 IF n<>1 THEN RAISE EXCEPTION 'Another real account private namespace was modified';END IF;
END $cascade$;
ROLLBACK;
SELECT 'PASS synthetic due-account solo retirement, final-readiness true, atomic Auth SQL cascade and independent real-account namespace preservation; rolled back' result;