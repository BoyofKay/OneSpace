-- Transactional regression test for invitation revocation and replacement.
BEGIN;
-- Transient test accounts and invitations: nothing survives ROLLBACK.
INSERT INTO auth.users
(id,instance_id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
VALUES
('a1111111-1111-4111-8111-111111111111','00000000-0000-0000-0000-000000000000','authenticated','authenticated','onespace-qa-a@example.invalid','not-a-login',now(),'{"provider":"email","providers":["email"]}'::jsonb,'{"display_name":"QA A"}'::jsonb,now(),now()),
('b2222222-2222-4222-8222-222222222222','00000000-0000-0000-0000-000000000000','authenticated','authenticated','onespace-qa-b@example.invalid','not-a-login',now(),'{"provider":"email","providers":["email"]}'::jsonb,'{"display_name":"QA B"}'::jsonb,now(),now());
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','a1111111-1111-4111-8111-111111111111',true);
SELECT set_config('onespace_test.space',public.create_space()::text,true);
SELECT set_config('onespace_test.first_code',public.create_invitation(current_setting('onespace_test.space')::uuid),true);
SELECT set_config('onespace_test.revocations',public.revoke_pending_invitation(current_setting('onespace_test.space')::uuid)::text,true);
DO $$
BEGIN
  IF current_setting('onespace_test.revocations')<>'1'
  THEN RAISE EXCEPTION 'Inviter did not revoke exactly one invitation'; END IF;
END $$;
SELECT set_config('request.jwt.claim.sub','b2222222-2222-4222-8222-222222222222',true);
DO $$
DECLARE denied boolean:=false; rejected boolean:=false;
BEGIN
 BEGIN
  PERFORM public.revoke_pending_invitation(current_setting('onespace_test.space')::uuid);
 EXCEPTION WHEN OTHERS THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'Outsider revoked another persons invitation'; END IF;
 BEGIN
  PERFORM public.accept_invitation(current_setting('onespace_test.first_code'));
 EXCEPTION WHEN OTHERS THEN rejected:=true;
 END;
 IF NOT rejected THEN RAISE EXCEPTION 'Revoked code was accepted'; END IF;
END $$;
SELECT set_config('request.jwt.claim.sub','a1111111-1111-4111-8111-111111111111',true);
SELECT set_config('onespace_test.second_code',public.create_invitation(current_setting('onespace_test.space')::uuid),true);
SELECT set_config('request.jwt.claim.sub','b2222222-2222-4222-8222-222222222222',true);
SELECT public.accept_invitation(current_setting('onespace_test.second_code'));
DO $$
BEGIN
 IF (SELECT count(*) FROM public.space_members WHERE space_id=current_setting('onespace_test.space')::uuid)<>2
 THEN RAISE EXCEPTION 'Replacement invitation did not pair partners'; END IF;
END $$;
SELECT 'PASS: authorized revocation, revoked-code rejection and replacement pairing' as test_result;
ROLLBACK;
