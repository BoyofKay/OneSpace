-- QA only: synthetic A/B/C lifecycle, never existing accounts.
-- ALL changes, including auth.users, are rolled back. No physical Storage
-- files are removed; backend shared-file queues remain after SQL deletion.
BEGIN;
SELECT set_config('qa.a',gen_random_uuid()::text,true);
SELECT set_config('qa.b',gen_random_uuid()::text,true);
SELECT set_config('qa.c',gen_random_uuid()::text,true);
INSERT INTO auth.users(id,aud,role,email,encrypted_password,email_confirmed_at)
SELECT id,'authenticated','authenticated',
 'qa-abc-'||id::text||'@example.invalid','not-a-real-password',now()
FROM (VALUES(current_setting('qa.a')::uuid),
 (current_setting('qa.b')::uuid),(current_setting('qa.c')::uuid)) AS users(id);
INSERT INTO public.spaces(created_by,name) VALUES
 (current_setting('qa.a')::uuid,'Synthetic A plus B')
 RETURNING id;
-- The last RETURNING is deliberately not used; retrieve from name+creator.
SELECT set_config('qa.ab',(SELECT id::text FROM public.spaces
 WHERE created_by=current_setting('qa.a')::uuid AND name='Synthetic A plus B'
 LIMIT 1),true);
INSERT INTO public.space_members(space_id,user_id)
VALUES(current_setting('qa.ab')::uuid,current_setting('qa.a')::uuid),
      (current_setting('qa.ab')::uuid,current_setting('qa.b')::uuid);
SELECT set_config('request.jwt.claim.sub',current_setting('qa.a'),true);
SET LOCAL ROLE authenticated;
INSERT INTO public.notes(private_space_id,created_by,title,visibility)
VALUES(current_setting('qa.a')::uuid,current_setting('qa.a')::uuid,
 'A private note must always survive','private');
INSERT INTO public.notes(space_id,created_by,title,visibility)
VALUES(current_setting('qa.ab')::uuid,current_setting('qa.a')::uuid,
 'AB shared note must disappear','shared');
SELECT set_config('request.jwt.claim.sub',current_setting('qa.b'),true);
INSERT INTO public.notes(private_space_id,created_by,title,visibility)
VALUES(current_setting('qa.b')::uuid,current_setting('qa.b')::uuid,
 'B private note never belongs to C','private');
INSERT INTO public.notes(space_id,created_by,title,visibility)
VALUES(current_setting('qa.ab')::uuid,current_setting('qa.b')::uuid,
 'B relationship content never belongs to C','shared');
RESET ROLE;
GRANT USAGE ON SCHEMA private TO authenticated;
GRANT EXECUTE ON FUNCTION private.qa_close_relationship_v2(uuid,text,text)
 TO authenticated;
UPDATE private.qa_relationship_v2_gate SET enabled=true WHERE id=1;
SELECT set_config('request.jwt.claim.sub',current_setting('qa.a'),true);
SET LOCAL ROLE authenticated;
DO $separate$
DECLARE outcome jsonb;
BEGIN
 outcome:=private.qa_close_relationship_v2(
 current_setting('qa.ab')::uuid,'remove_partner','DELETE SHARED CONTENT');
 IF outcome->>'status'<>'shared_db_removed_storage_purge_pending'
  OR (outcome->>'members_unpaired')::integer<>2 THEN
  RAISE EXCEPTION 'A/B relationship was not permanently deleted';END IF;
END $separate$;
RESET ROLE;
DO $between$
DECLARE n integer;
BEGIN
 SELECT count(*) INTO n FROM public.notes
 WHERE space_id=current_setting('qa.ab')::uuid;
 IF n<>0 THEN RAISE EXCEPTION 'AB shared notes survived separation';END IF;
 SELECT count(*) INTO n FROM public.space_members
 WHERE space_id=current_setting('qa.ab')::uuid;
 IF n<>0 THEN RAISE EXCEPTION 'AB membership survived separation';END IF;
 SELECT count(*) INTO n FROM public.notes
 WHERE private_space_id IN(current_setting('qa.a')::uuid,current_setting('qa.b')::uuid);
 IF n<>2 THEN RAISE EXCEPTION 'A/B private notes were lost';END IF;
END $between$;
INSERT INTO public.spaces(created_by,name)
VALUES(current_setting('qa.a')::uuid,'Synthetic A plus C');
SELECT set_config('qa.ac',(SELECT id::text FROM public.spaces
 WHERE created_by=current_setting('qa.a')::uuid AND name='Synthetic A plus C'
 LIMIT 1),true);
INSERT INTO public.space_members(space_id,user_id)
VALUES(current_setting('qa.ac')::uuid,current_setting('qa.a')::uuid),
      (current_setting('qa.ac')::uuid,current_setting('qa.c')::uuid);
SELECT set_config('request.jwt.claim.sub',current_setting('qa.c'),true);
SET LOCAL ROLE authenticated;
DO $c$
DECLARE n integer;
BEGIN
 SELECT count(*) INTO n FROM public.notes WHERE
 private_space_id IN(current_setting('qa.a')::uuid,current_setting('qa.b')::uuid)
 OR space_id=current_setting('qa.ab')::uuid;
 IF n<>0 THEN RAISE EXCEPTION 'C sees former partner private or AB content';END IF;
 SELECT count(*) INTO n FROM public.notes
 WHERE space_id=current_setting('qa.ac')::uuid;
 IF n<>0 THEN RAISE EXCEPTION 'C inherited stale relationship data';END IF;
END $c$;
INSERT INTO public.notes(space_id,created_by,title,visibility)
VALUES(current_setting('qa.ac')::uuid,current_setting('qa.c')::uuid,
 'Only new AC couple sees this','shared');
RESET ROLE;
DO $assert_couple$
DECLARE n integer;
BEGIN
 SELECT count(*) INTO n FROM public.notes WHERE
 space_id=current_setting('qa.ac')::uuid AND visibility='shared';
 IF n<>1 THEN RAISE EXCEPTION 'New AC relationship missing own shared note';END IF;
 SELECT count(*) INTO n FROM public.notes
 WHERE private_space_id=current_setting('qa.b')::uuid;
 IF n<>1 THEN RAISE EXCEPTION 'Former B lost private content';END IF;
END $assert_couple$;
SELECT set_config('request.jwt.claim.sub',current_setting('qa.b'),true);
SET LOCAL ROLE authenticated;
DO $b$
DECLARE n integer;
BEGIN
 SELECT count(*) INTO n FROM public.notes
 WHERE space_id=current_setting('qa.ac')::uuid;
 IF n<>0 THEN RAISE EXCEPTION 'B sees new AC relationship';END IF;
 SELECT count(*) INTO n FROM public.notes
 WHERE private_space_id=current_setting('qa.b')::uuid;
 IF n<>1 THEN RAISE EXCEPTION 'B cannot see own private record after separation';END IF;
END $b$;
ROLLBACK;
SELECT 'PASS synthetic A+B deletion and new A+C pair isolate all prior shared and private Notes; B private survives; rolled back' result;