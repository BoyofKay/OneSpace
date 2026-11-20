-- QA storage.objects RLS with owner private media: simulated metadata, not file bytes.
-- All DB writes in this test roll back.
BEGIN;
SELECT set_config('qa.owner',(SELECT user_id::text FROM public.space_members ORDER BY space_id,user_id LIMIT 1),true);
SELECT set_config('qa.peer',(SELECT user_id::text FROM public.space_members WHERE space_id=(SELECT space_id FROM public.space_members WHERE user_id::text=current_setting('qa.owner') LIMIT 1) AND user_id::text<>current_setting('qa.owner') LIMIT 1),true);
SELECT set_config('qa.outsider',(SELECT user_id::text FROM public.space_members WHERE space_id<>(SELECT space_id FROM public.space_members WHERE user_id::text=current_setting('qa.owner') LIMIT 1) LIMIT 1),true);
SELECT set_config('request.jwt.claim.sub',current_setting('qa.owner'),true);
SET LOCAL ROLE authenticated;
DO $qa$
DECLARE me uuid:=current_setting('qa.owner')::uuid;
 peer uuid:=current_setting('qa.peer')::uuid;
 outsider uuid:=current_setting('qa.outsider')::uuid;
 note_id uuid;memory_id uuid;trip_id uuid;
 n_path text;m_path text;t_path text;counts int;
BEGIN
 IF me IS NULL OR peer IS NULL OR outsider IS NULL THEN
  RAISE EXCEPTION 'Owner, partner and outsider required';END IF;
 INSERT INTO public.notes(private_space_id,created_by,visibility,title)
 VALUES(me,me,'private','QA object private note') RETURNING id INTO note_id;
 INSERT INTO public.memories(private_space_id,created_by,visibility,title,memory_date)
 VALUES(me,me,'private','QA object private memory',DATE '2026-11-20') RETURNING id INTO memory_id;
 INSERT INTO public.shared_trips(private_space_id,created_by,visibility,title)
 VALUES(me,me,'private','QA object private trip') RETURNING id INTO trip_id;
 n_path:=note_id::text||'/'||me::text||'/'||gen_random_uuid()::text||'.jpg';
 m_path:=memory_id::text||'/'||me::text||'/'||gen_random_uuid()::text||'.jpg';
 t_path:=trip_id::text||'/'||me::text||'/'||gen_random_uuid()::text||'.pdf';
 INSERT INTO storage.objects(bucket_id,name,owner_id) VALUES
 ('onespace-private-note-images',n_path,me::text),
 ('onespace-private-memory-photos',m_path,me::text),
 ('onespace-private-trip-documents',t_path,me::text);
 SELECT count(*) INTO counts FROM storage.objects WHERE name IN(n_path,m_path,t_path);
 IF counts<>0 THEN RAISE EXCEPTION 'Unattached objects should not be readable by parent view';END IF;
 INSERT INTO public.note_images(note_id,created_by,object_path,storage_bucket_id)
 VALUES(note_id,me,n_path,'onespace-private-note-images');
 INSERT INTO public.memory_photos(memory_id,created_by,object_path,storage_bucket_id,mime_type,byte_size)
 VALUES(memory_id,me,m_path,'onespace-private-memory-photos','image/jpeg',100);
 INSERT INTO public.trip_attachments(trip_id,created_by,object_path,storage_bucket_id,
  title,file_name,mime_type,file_size)
 VALUES(trip_id,me,t_path,'onespace-private-trip-documents',
 'QA ticket','ticket.pdf','application/pdf',200);
 SELECT count(*) INTO counts FROM storage.objects WHERE name IN(n_path,m_path,t_path);
 IF counts<>3 THEN RAISE EXCEPTION 'Owner cannot retrieve all three attached private objects';END IF;
 PERFORM set_config('request.jwt.claim.sub',peer::text,true);
 SELECT count(*) INTO counts FROM storage.objects WHERE name IN(n_path,m_path,t_path);
 IF counts<>0 THEN RAISE EXCEPTION 'Partner can see account-private bytes';END IF;
 PERFORM set_config('request.jwt.claim.sub',outsider::text,true);
 SELECT count(*) INTO counts FROM storage.objects WHERE name IN(n_path,m_path,t_path);
 IF counts<>0 THEN RAISE EXCEPTION 'Outsider sees account-private bytes';END IF;
 PERFORM set_config('request.jwt.claim.sub',me::text,true);
 BEGIN
  INSERT INTO storage.objects(bucket_id,name,owner_id)
  VALUES('onespace-private-note-images',note_id::text||'/'||peer::text||'/'||
    gen_random_uuid()::text||'.jpg',me::text);
  RAISE EXCEPTION 'BUG: forged peer path accepted in owner bucket';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM LIKE 'BUG:%' THEN RAISE; END IF;END;
 BEGIN
  INSERT INTO storage.objects(bucket_id,name,owner_id)
  VALUES('onespace-private-trip-documents',
    note_id::text||'/'||me::text||'/'||gen_random_uuid()::text||'.pdf',me::text);
  RAISE EXCEPTION 'BUG: non-trip parent accepted in trip bucket';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM LIKE 'BUG:%' THEN RAISE; END IF;END;
END $qa$;
ROLLBACK;
SELECT 'PASS private note/memory/trip Storage INSERT and signed-file access RLS, partner/outsider denial, cross-parent/path rejects; rolled back' result;