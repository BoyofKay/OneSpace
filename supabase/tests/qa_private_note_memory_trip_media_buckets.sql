-- QA-only rollback: metadata + private storage bucket ownership, no real media uploaded.
BEGIN;
SELECT set_config('qa.owner',(SELECT user_id::text FROM public.space_members ORDER BY space_id,user_id LIMIT 1),true);
SELECT set_config('qa.space',(SELECT space_id::text FROM public.space_members WHERE user_id::text=current_setting('qa.owner') LIMIT 1),true);
SELECT set_config('qa.peer',(SELECT user_id::text FROM public.space_members WHERE space_id::text=current_setting('qa.space') AND user_id::text<>current_setting('qa.owner') LIMIT 1),true);
SELECT set_config('qa.outside',(SELECT user_id::text FROM public.space_members WHERE space_id::text<>current_setting('qa.space') LIMIT 1),true);
SELECT set_config('request.jwt.claim.sub',current_setting('qa.owner'),true);
SET LOCAL ROLE authenticated;
DO $qa$
DECLARE own uuid:=current_setting('qa.owner')::uuid;
 peer uuid:=current_setting('qa.peer')::uuid;
 outsider uuid:=current_setting('qa.outside')::uuid;
 shared_space uuid:=current_setting('qa.space')::uuid;
 n_private uuid;m_private uuid;t_private uuid;
 n_pair uuid;m_pair uuid;t_pair uuid;
 image_id uuid;photo_id uuid;doc_id uuid;
 image_path text;photo_path text;doc_path text;cnt integer;
BEGIN
 IF own IS NULL OR peer IS NULL OR outsider IS NULL THEN
   RAISE EXCEPTION 'Missing QA owner, partner or outsider fixture';END IF;
 INSERT INTO public.notes(private_space_id,created_by,visibility,title)
 VALUES(own,own,'private','QA personal note photo') RETURNING id INTO n_private;
 INSERT INTO public.notes(space_id,created_by,visibility,title)
 VALUES(shared_space,own,'shared','QA couple note photo') RETURNING id INTO n_pair;
 INSERT INTO public.memories(private_space_id,created_by,visibility,title)
 VALUES(own,own,'private','QA personal album') RETURNING id INTO m_private;
 INSERT INTO public.memories(space_id,created_by,visibility,title)
 VALUES(shared_space,own,'shared','QA couple album') RETURNING id INTO m_pair;
 INSERT INTO public.shared_trips(private_space_id,created_by,visibility,title)
 VALUES(own,own,'private','QA personal travel') RETURNING id INTO t_private;
 INSERT INTO public.shared_trips(space_id,created_by,visibility,title)
 VALUES(shared_space,own,'shared','QA couple travel') RETURNING id INTO t_pair;
 image_path:=n_private::text||'/'||own::text||'/'||gen_random_uuid()::text||'.jpg';
 photo_path:=m_private::text||'/'||own::text||'/'||gen_random_uuid()::text||'.jpg';
 doc_path:=t_private::text||'/'||own::text||'/'||gen_random_uuid()::text||'.pdf';
 INSERT INTO public.note_images(note_id,created_by,object_path,storage_bucket_id)
 VALUES(n_private,own,image_path,'onespace-private-note-images') RETURNING id INTO image_id;
 INSERT INTO public.memory_photos(memory_id,created_by,object_path,storage_bucket_id,mime_type,byte_size)
 VALUES(m_private,own,photo_path,'onespace-private-memory-photos','image/jpeg',100) RETURNING id INTO photo_id;
 INSERT INTO public.trip_attachments(trip_id,created_by,object_path,storage_bucket_id,
 title,file_name,mime_type,file_size)
 VALUES(t_private,own,doc_path,'onespace-private-trip-documents',
 'Test document','test.pdf','application/pdf',200) RETURNING id INTO doc_id;
 SELECT count(*) INTO cnt FROM public.note_images WHERE id=image_id;
 IF cnt<>1 THEN RAISE EXCEPTION 'Owner missing personal note image';END IF;
 SELECT count(*) INTO cnt FROM public.memory_photos WHERE id=photo_id;
 IF cnt<>1 THEN RAISE EXCEPTION 'Owner missing personal memory photo';END IF;
 SELECT count(*) INTO cnt FROM public.trip_attachments WHERE id=doc_id;
 IF cnt<>1 THEN RAISE EXCEPTION 'Owner missing personal travel doc';END IF;
 PERFORM set_config('request.jwt.claim.sub',peer::text,true);
 SELECT count(*) INTO cnt FROM public.note_images WHERE id=image_id;
 IF cnt<>0 THEN RAISE EXCEPTION 'Partner sees private note image';END IF;
 SELECT count(*) INTO cnt FROM public.memory_photos WHERE id=photo_id;
 IF cnt<>0 THEN RAISE EXCEPTION 'Partner sees private memory photo';END IF;
 SELECT count(*) INTO cnt FROM public.trip_attachments WHERE id=doc_id;
 IF cnt<>0 THEN RAISE EXCEPTION 'Partner sees private travel doc';END IF;
 PERFORM set_config('request.jwt.claim.sub',outsider::text,true);
 SELECT count(*) INTO cnt FROM public.memory_photos WHERE id=photo_id;
 IF cnt<>0 THEN RAISE EXCEPTION 'Outsider sees personal photo';END IF;
 PERFORM set_config('request.jwt.claim.sub',own::text,true);
 BEGIN
  INSERT INTO public.note_images(note_id,created_by,object_path,storage_bucket_id)
  VALUES(n_private,own,n_private::text||'/'||own::text||'/'||gen_random_uuid()::text||'.jpg','onespace-note-images');
  RAISE EXCEPTION 'BUG: private note attached in couple Storage';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM LIKE 'BUG:%' THEN RAISE;END IF;END;
 BEGIN
  INSERT INTO public.memory_photos(memory_id,created_by,object_path,storage_bucket_id,mime_type,byte_size)
  VALUES(m_private,own,m_private::text||'/'||own::text||'/'||gen_random_uuid()::text||'.jpg',
  'onespace-memory-photos','image/jpeg',100);
  RAISE EXCEPTION 'BUG: personal photo attached in couple Storage';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM LIKE 'BUG:%' THEN RAISE;END IF;END;
 BEGIN
  INSERT INTO public.trip_attachments(trip_id,created_by,object_path,storage_bucket_id,
   title,file_name,mime_type,file_size)
  VALUES(t_private,own,t_private::text||'/'||own::text||'/'||gen_random_uuid()::text||'.pdf',
   'onespace-trip-documents','Wrong bucket','test.pdf','application/pdf',200);
  RAISE EXCEPTION 'BUG: personal travel doc attached in couple Storage';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM LIKE 'BUG:%' THEN RAISE;END IF;END;
 BEGIN
  UPDATE public.note_images SET storage_bucket_id='onespace-note-images' WHERE id=image_id;
  RAISE EXCEPTION 'BUG: personal image reassigned to couple Storage';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM LIKE 'BUG:%' THEN RAISE;END IF;END;
 BEGIN
  UPDATE public.memory_photos SET memory_id=m_pair WHERE id=photo_id;
  RAISE EXCEPTION 'BUG: personal photo reassigned to couple memory';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM LIKE 'BUG:%' THEN RAISE;END IF;END;
 BEGIN
  UPDATE public.trip_attachments SET trip_id=t_pair WHERE id=doc_id;
  RAISE EXCEPTION 'BUG: personal document reassigned to couple trip';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM LIKE 'BUG:%' THEN RAISE;END IF;END;
END $qa$;
ROLLBACK;
SELECT 'PASS private note, memory and trip attachment bucket ownership with partner/outsider denial and immutable scope; rolled back' result;