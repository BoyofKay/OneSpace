-- QA rollback: due account initiates exact current pair deletion, whether
-- space owner (A/B) or invited partner (C/D). Surviving user's private data
-- remains. No real account is modified and the gates roll back to OFF.
BEGIN;
SELECT set_config('qa.a',gen_random_uuid()::text,true);
SELECT set_config('qa.b',gen_random_uuid()::text,true);
SELECT set_config('qa.c',gen_random_uuid()::text,true);
SELECT set_config('qa.d',gen_random_uuid()::text,true);
INSERT INTO auth.users(id,aud,role,email,encrypted_password,email_confirmed_at)
SELECT id,'authenticated','authenticated',
 'qa-due-couple-'||id::text||'@example.invalid','synthetic',now()
FROM (VALUES(current_setting('qa.a')::uuid),(current_setting('qa.b')::uuid),
 (current_setting('qa.c')::uuid),(current_setting('qa.d')::uuid)) v(id);
INSERT INTO public.spaces(name,created_by) VALUES
 ('QA due pair AB',current_setting('qa.a')::uuid),
 ('QA due pair CD',current_setting('qa.c')::uuid);
SELECT set_config('qa.ab',(SELECT id::text FROM public.spaces
 WHERE name='QA due pair AB' AND created_by=current_setting('qa.a')::uuid),true);
SELECT set_config('qa.cd',(SELECT id::text FROM public.spaces
 WHERE name='QA due pair CD' AND created_by=current_setting('qa.c')::uuid),true);
INSERT INTO public.space_members(space_id,user_id)
VALUES(current_setting('qa.ab')::uuid,current_setting('qa.a')::uuid),
      (current_setting('qa.ab')::uuid,current_setting('qa.b')::uuid),
      (current_setting('qa.cd')::uuid,current_setting('qa.c')::uuid),
      (current_setting('qa.cd')::uuid,current_setting('qa.d')::uuid);
-- Seed owner/private and pair-shared Notes for both relationships.
INSERT INTO public.notes(private_space_id,created_by,title,visibility) VALUES
 (current_setting('qa.a')::uuid,current_setting('qa.a')::uuid,'QA A personal','private'),
 (current_setting('qa.b')::uuid,current_setting('qa.b')::uuid,'QA B personal','private'),
 (current_setting('qa.c')::uuid,current_setting('qa.c')::uuid,'QA C personal','private'),
 (current_setting('qa.d')::uuid,current_setting('qa.d')::uuid,'QA D personal','private');
INSERT INTO public.notes(space_id,created_by,title,visibility) VALUES
 (current_setting('qa.ab')::uuid,current_setting('qa.a')::uuid,'QA AB shared','shared'),
 (current_setting('qa.cd')::uuid,current_setting('qa.d')::uuid,'QA CD shared','shared');
INSERT INTO public.account_deletion_requests(user_id,requested_at,purge_after)
VALUES(current_setting('qa.a')::uuid,now()-interval '8 days',now()-interval '1 day'),
      (current_setting('qa.d')::uuid,now()-interval '8 days',now()-interval '1 day');
SET LOCAL ROLE authenticated;
DO $client$
BEGIN
 BEGIN
  PERFORM public.qa_due_account_close_current_relationship(current_setting('qa.a')::uuid);
  RAISE EXCEPTION 'BUG: ordinary app can close pair via service function';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM LIKE 'BUG:%' THEN RAISE;END IF;END;
END $client$;
RESET ROLE;
SET LOCAL ROLE service_role;
DO $closed$
BEGIN
 BEGIN
  PERFORM public.qa_due_account_close_current_relationship(current_setting('qa.a')::uuid);
  RAISE EXCEPTION 'BUG: relationship deleted behind disabled service gates';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM LIKE 'BUG:%' THEN RAISE;END IF;END;
END $closed$;
RESET ROLE;
UPDATE private.qa_account_v2_gate SET enabled=true WHERE id=1;
UPDATE private.qa_relationship_v2_gate SET enabled=true WHERE id=1;
SET LOCAL ROLE service_role;
DO $service$
DECLARE result jsonb;n int;
BEGIN
 result:=public.qa_due_account_close_current_relationship(current_setting('qa.a')::uuid);
 IF result->>'closed_on_behalf_of_due_account'<>'true' OR
  result->>'action'<>'delete_space' THEN
  RAISE EXCEPTION 'Owner due account A did not close pair AB';END IF;
 result:=public.qa_due_account_close_current_relationship(current_setting('qa.d')::uuid);
 IF result->>'closed_on_behalf_of_due_account'<>'true' OR
  result->>'action'<>'leave_space' THEN
  RAISE EXCEPTION 'Invited due account D did not close pair CD';END IF;
 result:=public.qa_due_account_close_current_relationship(current_setting('qa.a')::uuid);
 IF result->>'status'<>'already_unpaired' THEN
  RAISE EXCEPTION 'Repeated due-account closure not idempotent';END IF;
 SELECT count(*) INTO n FROM public.notes WHERE
  space_id IN(current_setting('qa.ab')::uuid,current_setting('qa.cd')::uuid);
 IF n<>0 THEN RAISE EXCEPTION 'Former shared content survived due account closure';END IF;
 SELECT count(*) INTO n FROM public.notes WHERE
  private_space_id IN(current_setting('qa.a')::uuid,current_setting('qa.b')::uuid,
                      current_setting('qa.c')::uuid,current_setting('qa.d')::uuid);
 IF n<>4 THEN RAISE EXCEPTION 'Former or surviving partner private data lost';END IF;
 SELECT count(*) INTO n FROM public.user_private_spaces
 WHERE owner_id IN(current_setting('qa.a')::uuid,current_setting('qa.b')::uuid,
                   current_setting('qa.c')::uuid,current_setting('qa.d')::uuid);
 IF n<>4 THEN RAISE EXCEPTION 'Permanent private namespaces not preserved';END IF;
END $service$;
ROLLBACK;
SELECT 'PASS due owner and invited partner close only their former couple; four private namespaces/Notes survive, service gated, repeat idempotent; rolled back' result;