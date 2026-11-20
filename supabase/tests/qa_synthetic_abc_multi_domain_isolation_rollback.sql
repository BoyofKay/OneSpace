-- QA rollback, no existing user touched. A/B separation then A/C pairing
-- must isolate Activities, Memories, Goals, Contacts, Trips and Places,
-- in addition to the original Note-only test.
BEGIN;
SELECT set_config('qa.a',gen_random_uuid()::text,true);
SELECT set_config('qa.b',gen_random_uuid()::text,true);
SELECT set_config('qa.c',gen_random_uuid()::text,true);
INSERT INTO auth.users(id,aud,role,email,encrypted_password,email_confirmed_at)
SELECT u,'authenticated','authenticated',
 'qa-abc-modules-'||u::text||'@example.invalid','synthetic',now()
FROM (VALUES(current_setting('qa.a')::uuid),
 (current_setting('qa.b')::uuid),(current_setting('qa.c')::uuid)) v(u);
INSERT INTO public.spaces(created_by,name)
VALUES(current_setting('qa.a')::uuid,'QA modules old AB');
SELECT set_config('qa.ab',(SELECT id::text FROM public.spaces
 WHERE created_by=current_setting('qa.a')::uuid AND name='QA modules old AB'),true);
INSERT INTO public.space_members(space_id,user_id)
VALUES(current_setting('qa.ab')::uuid,current_setting('qa.a')::uuid),
      (current_setting('qa.ab')::uuid,current_setting('qa.b')::uuid);

-- Fixture writes are performed AS the authenticated owner,
-- matching the ownership guard's true client rules.
SELECT set_config('request.jwt.claim.sub',current_setting('qa.a'),true);
SET LOCAL ROLE authenticated;
INSERT INTO public.activities(private_space_id,created_by,title,visibility)
VALUES(current_setting('qa.a')::uuid,current_setting('qa.a')::uuid,'A protected Activity','private');
INSERT INTO public.memories(private_space_id,created_by,title,memory_date,visibility)
VALUES(current_setting('qa.a')::uuid,current_setting('qa.a')::uuid,'A protected Memory',CURRENT_DATE,'private');
INSERT INTO public.goals(private_space_id,created_by,title,visibility)
VALUES(current_setting('qa.a')::uuid,current_setting('qa.a')::uuid,'A protected Goal','private');
INSERT INTO public.saved_contacts(private_space_id,created_by,label,visibility)
VALUES(current_setting('qa.a')::uuid,current_setting('qa.a')::uuid,'A private contact','private');
INSERT INTO public.shared_trips(private_space_id,created_by,title,visibility)
VALUES(current_setting('qa.a')::uuid,current_setting('qa.a')::uuid,'A private Trip','private');
INSERT INTO public.places(private_space_id,created_by,name,visibility)
VALUES(current_setting('qa.a')::uuid,current_setting('qa.a')::uuid,'A private Place','private');
RESET ROLE;
SELECT set_config('request.jwt.claim.sub',current_setting('qa.b'),true);
SET LOCAL ROLE authenticated;
INSERT INTO public.activities(private_space_id,created_by,title,visibility)
VALUES(current_setting('qa.b')::uuid,current_setting('qa.b')::uuid,'B protected Activity','private');
INSERT INTO public.memories(private_space_id,created_by,title,memory_date,visibility)
VALUES(current_setting('qa.b')::uuid,current_setting('qa.b')::uuid,'B protected Memory',CURRENT_DATE,'private');
INSERT INTO public.goals(private_space_id,created_by,title,visibility)
VALUES(current_setting('qa.b')::uuid,current_setting('qa.b')::uuid,'B protected Goal','private');
INSERT INTO public.saved_contacts(private_space_id,created_by,label,visibility)
VALUES(current_setting('qa.b')::uuid,current_setting('qa.b')::uuid,'B private contact','private');
INSERT INTO public.shared_trips(private_space_id,created_by,title,visibility)
VALUES(current_setting('qa.b')::uuid,current_setting('qa.b')::uuid,'B private Trip','private');
INSERT INTO public.places(private_space_id,created_by,name,visibility)
VALUES(current_setting('qa.b')::uuid,current_setting('qa.b')::uuid,'B private Place','private');
INSERT INTO public.activities(space_id,created_by,title,visibility)
VALUES(current_setting('qa.ab')::uuid,current_setting('qa.b')::uuid,'AB discarded Activity','shared');
INSERT INTO public.memories(space_id,created_by,title,memory_date,visibility)
VALUES(current_setting('qa.ab')::uuid,current_setting('qa.b')::uuid,'AB discarded Memory',CURRENT_DATE,'shared');
INSERT INTO public.goals(space_id,created_by,title,visibility)
VALUES(current_setting('qa.ab')::uuid,current_setting('qa.b')::uuid,'AB discarded Goal','shared');
INSERT INTO public.saved_contacts(space_id,created_by,label,visibility)
VALUES(current_setting('qa.ab')::uuid,current_setting('qa.b')::uuid,'AB discarded contact','shared');
INSERT INTO public.shared_trips(space_id,created_by,title,visibility)
VALUES(current_setting('qa.ab')::uuid,current_setting('qa.b')::uuid,'AB discarded Trip','shared');
INSERT INTO public.places(space_id,created_by,name,visibility)
VALUES(current_setting('qa.ab')::uuid,current_setting('qa.b')::uuid,'AB discarded Place','shared');
RESET ROLE;

UPDATE private.qa_relationship_v2_gate SET enabled=true WHERE id=1;
GRANT USAGE ON SCHEMA private TO authenticated;
GRANT EXECUTE ON FUNCTION private.qa_close_relationship_v2(uuid,text,text) TO authenticated;
SELECT set_config('request.jwt.claim.sub',current_setting('qa.a'),true);
SET LOCAL ROLE authenticated;
DO $break$
DECLARE result jsonb;
BEGIN
 result:=private.qa_close_relationship_v2(
  current_setting('qa.ab')::uuid,'remove_partner','DELETE SHARED CONTENT');
 IF result->>'status'<>'shared_db_removed_storage_purge_pending' THEN
  RAISE EXCEPTION 'AB couple deletion failed';END IF;
END $break$;
RESET ROLE;
INSERT INTO public.spaces(created_by,name)
VALUES(current_setting('qa.a')::uuid,'QA modules new AC');
SELECT set_config('qa.ac',(SELECT id::text FROM public.spaces
 WHERE created_by=current_setting('qa.a')::uuid AND name='QA modules new AC'),true);
INSERT INTO public.space_members(space_id,user_id)
VALUES(current_setting('qa.ac')::uuid,current_setting('qa.a')::uuid),
      (current_setting('qa.ac')::uuid,current_setting('qa.c')::uuid);
INSERT INTO public.activities(space_id,created_by,title,visibility)
VALUES(current_setting('qa.ac')::uuid,current_setting('qa.c')::uuid,'AC new Activity','shared');

-- Verify scope visibility using actual authenticated/RLS filtering.
-- Query under partner C's authenticated RLS: C must see none of the
-- deleted A+B shared records or either person's private rows.
SELECT set_config('request.jwt.claim.sub',current_setting('qa.c'),true);
SET LOCAL ROLE authenticated;
DO $c_privacy$
DECLARE area text;n int;
BEGIN
 FOR area IN SELECT unnest(ARRAY['activities','memories','goals',
 'saved_contacts','shared_trips','places']) LOOP
  EXECUTE format('SELECT count(*) FROM public.%I WHERE private_space_id IN ($1,$2) OR space_id=$3',area)
   INTO n USING current_setting('qa.a')::uuid,
   current_setting('qa.b')::uuid,current_setting('qa.ab')::uuid;
  IF n<>0 THEN RAISE EXCEPTION 'C sees old AB/private content in %',area;END IF;
 END LOOP;
END $c_privacy$;
RESET ROLE;
SELECT set_config('request.jwt.claim.sub',current_setting('qa.b'),true);
SET LOCAL ROLE authenticated;
DO $b_privacy$
DECLARE area text;n int;
BEGIN
 FOR area IN SELECT unnest(ARRAY['activities','memories','goals',
 'saved_contacts','shared_trips','places']) LOOP
  EXECUTE format('SELECT count(*) FROM public.%I WHERE private_space_id=$1',area)
   INTO n USING current_setting('qa.b')::uuid;
  IF n<>1 THEN RAISE EXCEPTION 'B cannot see own private data in %',area;END IF;
 END LOOP;
END $b_privacy$;
RESET ROLE;
-- A new shared Activity is invisible to B and visible to C.
SELECT set_config('request.jwt.claim.sub',current_setting('qa.b'),true);
SET LOCAL ROLE authenticated;
DO $former$
DECLARE n int;
BEGIN
 SELECT count(*) INTO n FROM public.activities
 WHERE space_id=current_setting('qa.ac')::uuid AND title='AC new Activity';
 IF n<>0 THEN RAISE EXCEPTION 'Former B sees new AC Activity';END IF;
END $former$;
RESET ROLE;
SELECT set_config('request.jwt.claim.sub',current_setting('qa.c'),true);
SET LOCAL ROLE authenticated;
DO $new$
DECLARE n int;
BEGIN
 SELECT count(*) INTO n FROM public.activities
 WHERE space_id=current_setting('qa.ac')::uuid AND title='AC new Activity';
 IF n<>1 THEN RAISE EXCEPTION 'New C cannot see AC shared Activity';END IF;
END $new$;
ROLLBACK;
SELECT 'PASS A/B old shared rows gone across six modules, A/B private isolation retained after A/C re-pair, C sees only new shared Activity; all synthetic rollback' result;
