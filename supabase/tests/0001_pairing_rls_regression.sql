-- Run only against a throwaway local or test database, or a controlled project. This entire script rolls back.
BEGIN;
-- All test identities and records exist only inside this transaction.
INSERT INTO auth.users
  (id,instance_id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
VALUES
  ('a1111111-1111-4111-8111-111111111111','00000000-0000-0000-0000-000000000000','authenticated','authenticated','onespace-qa-a@example.invalid','not-a-login',now(),'{"provider":"email","providers":["email"]}'::jsonb,'{"display_name":"QA A"}'::jsonb,now(),now()),
  ('b2222222-2222-4222-8222-222222222222','00000000-0000-0000-0000-000000000000','authenticated','authenticated','onespace-qa-b@example.invalid','not-a-login',now(),'{"provider":"email","providers":["email"]}'::jsonb,'{"display_name":"QA B"}'::jsonb,now(),now()),
  ('c3333333-3333-4333-8333-333333333333','00000000-0000-0000-0000-000000000000','authenticated','authenticated','onespace-qa-c@example.invalid','not-a-login',now(),'{"provider":"email","providers":["email"]}'::jsonb,'{"display_name":"QA C"}'::jsonb,now(),now());
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','a1111111-1111-4111-8111-111111111111',true);
SELECT set_config('onespace_test.space_id',public.create_space()::text,true);
SELECT set_config('onespace_test.code',public.create_invitation(current_setting('onespace_test.space_id')::uuid),true);
INSERT INTO public.tasks(space_id,created_by,title,priority)
VALUES(current_setting('onespace_test.space_id')::uuid,auth.uid(),'QA shared plan','high');
SELECT set_config('onespace_test.task_id',
  (SELECT id::text FROM public.tasks WHERE title='QA shared plan'),true);
DO $$
BEGIN
 IF (SELECT count(*) FROM public.tasks WHERE id=current_setting('onespace_test.task_id')::uuid)<>1
 THEN RAISE EXCEPTION 'Creator cannot read task'; END IF;
END $$;
SELECT set_config('request.jwt.claim.sub','b2222222-2222-4222-8222-222222222222',true);
SELECT public.accept_invitation(current_setting('onespace_test.code'));
DO $$
BEGIN
 IF (SELECT count(*) FROM public.tasks WHERE id=current_setting('onespace_test.task_id')::uuid)<>1
 THEN RAISE EXCEPTION 'Partner cannot read task'; END IF;
 UPDATE public.tasks SET status='completed' WHERE id=current_setting('onespace_test.task_id')::uuid;
 IF NOT FOUND THEN RAISE EXCEPTION 'Partner cannot update task'; END IF;
END $$;
SELECT set_config('request.jwt.claim.sub','c3333333-3333-4333-8333-333333333333',true);
DO $$
DECLARE rejected boolean:=false;
BEGIN
 IF (SELECT count(*) FROM public.tasks WHERE space_id=current_setting('onespace_test.space_id')::uuid)<>0
 THEN RAISE EXCEPTION 'Outsider can read tasks'; END IF;
 IF (SELECT count(*) FROM public.profiles WHERE id='a1111111-1111-4111-8111-111111111111')<>0
 THEN RAISE EXCEPTION 'Outsider can read profiles'; END IF;
 UPDATE public.tasks SET title='QA changed by outsider' WHERE id=current_setting('onespace_test.task_id')::uuid;
 IF FOUND THEN RAISE EXCEPTION 'Outsider can modify tasks'; END IF;
 BEGIN
  PERFORM public.accept_invitation(current_setting('onespace_test.code'));
 EXCEPTION WHEN OTHERS THEN rejected:=true;
 END;
 IF NOT rejected THEN RAISE EXCEPTION 'Invitation replay succeeded'; END IF;
END $$;
SELECT 'PASS: shared spaces, partner changes, RLS isolation and one-time invites' AS result;
ROLLBACK;
