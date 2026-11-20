-- QA ONLY, every change is rolled back. Simulate deleting a two-member
-- relationship via DB foreign-key cascade, then verify both private namespaces
-- and account-owned files survive and remain isolated.
-- Does NOT enable a user-facing deletion endpoint or clean physical Storage.
BEGIN;
SELECT set_config('qa.space',
 (SELECT space_id::text FROM public.space_members
 GROUP BY space_id HAVING count(*)=2 ORDER BY space_id LIMIT 1),true);
SELECT set_config('qa.owner',
 (SELECT user_id::text FROM public.space_members
 WHERE space_id=current_setting('qa.space')::uuid ORDER BY user_id LIMIT 1),true);
SELECT set_config('qa.peer',
 (SELECT user_id::text FROM public.space_members
 WHERE space_id=current_setting('qa.space')::uuid
 AND user_id::text<>current_setting('qa.owner') LIMIT 1),true);
SELECT set_config('request.jwt.claim.sub',current_setting('qa.owner'),true);
SET LOCAL ROLE authenticated;
DO $fixture$
DECLARE a uuid:=current_setting('qa.owner')::uuid;
 b uuid:=current_setting('qa.peer')::uuid;sp uuid:=current_setting('qa.space')::uuid;
 na uuid;nb uuid;ns uuid; obj_path text;
BEGIN
 IF a IS NULL OR b IS NULL OR sp IS NULL THEN
 RAISE EXCEPTION 'Two QA members are required';END IF;
 INSERT INTO public.notes(private_space_id,created_by,visibility,title)
 VALUES(a,a,'private','QA private A survives') RETURNING id INTO na;
 PERFORM set_config('qa.note_a',na::text,true);
 INSERT INTO public.notes(space_id,created_by,visibility,title)
 VALUES(sp,a,'shared','QA pair-shared note permanently erased')
 RETURNING id INTO ns;
 PERFORM set_config('qa.note_shared',ns::text,true);
 obj_path:=na::text||'/'||a::text||'/'||gen_random_uuid()::text||'.jpg';
 INSERT INTO storage.objects(bucket_id,name,owner_id)
 VALUES('onespace-private-note-images',obj_path,a::text);
 INSERT INTO public.note_images(note_id,created_by,object_path,storage_bucket_id)
 VALUES(na,a,obj_path,'onespace-private-note-images');
 PERFORM set_config('qa.private_photo',obj_path,true);
 PERFORM set_config('request.jwt.claim.sub',b::text,true);
 INSERT INTO public.notes(private_space_id,created_by,visibility,title)
 VALUES(b,b,'private','QA private B survives') RETURNING id INTO nb;
 PERFORM set_config('qa.note_b',nb::text,true);
END $fixture$;
RESET ROLE;
-- Retired archive progress now cascades with relationship; keep real users.
DELETE FROM public.spaces WHERE id=current_setting('qa.space')::uuid;
SET LOCAL ROLE authenticated;
DO $after$
DECLARE a uuid:=current_setting('qa.owner')::uuid;
 b uuid:=current_setting('qa.peer')::uuid;sp uuid:=current_setting('qa.space')::uuid; n int;
BEGIN
 PERFORM set_config('request.jwt.claim.sub',a::text,true);
 SELECT count(*) INTO n FROM public.user_private_spaces WHERE owner_id=a;
 IF n<>1 THEN RAISE EXCEPTION 'Account A private namespace was deleted';END IF;
 SELECT count(*) INTO n FROM public.notes WHERE id=current_setting('qa.note_a')::uuid;
 IF n<>1 THEN RAISE EXCEPTION 'Account A private Note lost';END IF;
 SELECT count(*) INTO n FROM public.note_images WHERE note_id=current_setting('qa.note_a')::uuid;
 IF n<>1 THEN RAISE EXCEPTION 'Account A private file metadata lost';END IF;
 SELECT count(*) INTO n FROM storage.objects
 WHERE bucket_id='onespace-private-note-images' AND name=current_setting('qa.private_photo');
 IF n<>1 THEN RAISE EXCEPTION 'Account A private Storage object lost';END IF;
 SELECT count(*) INTO n FROM public.notes WHERE id=current_setting('qa.note_shared')::uuid;
 IF n<>0 THEN RAISE EXCEPTION 'Former couple shared Note survived';END IF;
 SELECT count(*) INTO n FROM public.space_members WHERE space_id=sp;
 IF n<>0 THEN RAISE EXCEPTION 'Former relationship membership survived';END IF;
 PERFORM set_config('request.jwt.claim.sub',b::text,true);
 SELECT count(*) INTO n FROM public.user_private_spaces WHERE owner_id=b;
 IF n<>1 THEN RAISE EXCEPTION 'Account B private namespace was deleted';END IF;
 SELECT count(*) INTO n FROM public.notes WHERE id=current_setting('qa.note_b')::uuid;
 IF n<>1 THEN RAISE EXCEPTION 'Account B private Note lost';END IF;
 SELECT count(*) INTO n FROM public.notes WHERE id=current_setting('qa.note_a')::uuid;
 IF n<>0 THEN RAISE EXCEPTION 'B can see A private Note';END IF;
 SELECT count(*) INTO n FROM storage.objects WHERE name=current_setting('qa.private_photo');
 IF n<>0 THEN RAISE EXCEPTION 'B can see A private Storage object';END IF;
END $after$;
ROLLBACK;
SELECT 'PASS couple FK removal cascades shared note and members; both owner private namespaces, personal notes and files survive, no partner leak; rolled back' result;