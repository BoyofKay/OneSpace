-- QA rollback: account-private namespace erase is explicit and separate from
-- relationship deletion. Erasing A's private namespace cannot erase B's rows
-- or a shared Note. Auth user is NOT deleted by this test.
BEGIN;
SELECT set_config('qa.space',(SELECT space_id::text FROM public.space_members
 GROUP BY space_id HAVING count(*)=2 ORDER BY space_id LIMIT 1),true);
SELECT set_config('qa.owner',(SELECT user_id::text FROM public.space_members
 WHERE space_id=current_setting('qa.space')::uuid ORDER BY user_id LIMIT 1),true);
SELECT set_config('qa.peer',(SELECT user_id::text FROM public.space_members
 WHERE space_id=current_setting('qa.space')::uuid
 AND user_id::text<>current_setting('qa.owner') LIMIT 1),true);
SELECT set_config('request.jwt.claim.sub',current_setting('qa.owner'),true);
SET LOCAL ROLE authenticated;
DO $qa$
DECLARE a uuid:=current_setting('qa.owner')::uuid;
 b uuid:=current_setting('qa.peer')::uuid;
 sp uuid:=current_setting('qa.space')::uuid;
 na uuid;nb uuid;ns uuid;trip_id uuid;trip_file_id uuid;
 file_path text;
BEGIN
 INSERT INTO public.notes(private_space_id,created_by,visibility,title)
 VALUES(a,a,'private','Account A own note') RETURNING id INTO na;
 INSERT INTO public.notes(space_id,created_by,visibility,title)
 VALUES(sp,a,'shared','Couple still present') RETURNING id INTO ns;
 INSERT INTO public.shared_trips(private_space_id,created_by,visibility,title)
 VALUES(a,a,'private','Account A trip') RETURNING id INTO trip_id;
 file_path:=trip_id::text||'/'||a::text||'/'||gen_random_uuid()::text||'.pdf';
 INSERT INTO public.trip_attachments(trip_id,created_by,storage_bucket_id,object_path,
 title,file_name,mime_type,file_size)
 VALUES(trip_id,a,'onespace-private-trip-documents',file_path,
 'Personal flight','flight.pdf','application/pdf',401)
 RETURNING id INTO trip_file_id;
 PERFORM set_config('qa.note_a',na::text,true);
 PERFORM set_config('qa.note_shared',ns::text,true);
 PERFORM set_config('qa.trip_a',trip_id::text,true);
 PERFORM set_config('qa.trip_file_a',trip_file_id::text,true);
 PERFORM set_config('request.jwt.claim.sub',b::text,true);
 INSERT INTO public.notes(private_space_id,created_by,visibility,title)
 VALUES(b,b,'private','Account B own note') RETURNING id INTO nb;
 PERFORM set_config('qa.note_b',nb::text,true);
END $qa$;
RESET ROLE;
DELETE FROM public.user_private_spaces WHERE owner_id=current_setting('qa.owner')::uuid;
DO $assert$
DECLARE n integer;
BEGIN
 SELECT count(*) INTO n FROM public.notes WHERE id=current_setting('qa.note_a')::uuid;
 IF n<>0 THEN RAISE EXCEPTION 'Account A private Note survived namespace deletion';END IF;
 SELECT count(*) INTO n FROM public.shared_trips WHERE id=current_setting('qa.trip_a')::uuid;
 IF n<>0 THEN RAISE EXCEPTION 'Account A private Trip survived namespace deletion';END IF;
 SELECT count(*) INTO n FROM public.trip_attachments WHERE id=current_setting('qa.trip_file_a')::uuid;
 IF n<>0 THEN RAISE EXCEPTION 'Account A private document reference survived';END IF;
 SELECT count(*) INTO n FROM public.notes WHERE id=current_setting('qa.note_b')::uuid;
 IF n<>1 THEN RAISE EXCEPTION 'Partner private Note lost';END IF;
 SELECT count(*) INTO n FROM public.user_private_spaces WHERE owner_id=current_setting('qa.peer')::uuid;
 IF n<>1 THEN RAISE EXCEPTION 'Partner private namespace lost';END IF;
 SELECT count(*) INTO n FROM public.notes WHERE id=current_setting('qa.note_shared')::uuid;
 IF n<>1 THEN RAISE EXCEPTION 'Erasing private namespace erased shared space';END IF;
 SELECT count(*) INTO n FROM public.space_members WHERE space_id=current_setting('qa.space')::uuid;
 IF n<>2 THEN RAISE EXCEPTION 'Private namespace deletion changed couple membership';END IF;
END $assert$;
ROLLBACK;
SELECT 'PASS deleting account A private namespace cascades own notes/trips/documents while preserving account B private and pair-shared rows; rolled back' result;