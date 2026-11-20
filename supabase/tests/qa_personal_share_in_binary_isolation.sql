-- QA rollback: incoming image/PDF in owner's account bucket; partner/outsider
-- cannot read the metadata or Storage object; cross-scope attachments rejected.
BEGIN;
SELECT set_config('qa.owner',(SELECT user_id::text FROM public.space_members ORDER BY space_id,user_id LIMIT 1),true);
SELECT set_config('qa.space',(SELECT space_id::text FROM public.space_members WHERE user_id::text=current_setting('qa.owner') LIMIT 1),true);
SELECT set_config('qa.peer',(SELECT user_id::text FROM public.space_members WHERE space_id::text=current_setting('qa.space') AND user_id::text<>current_setting('qa.owner') LIMIT 1),true);
SELECT set_config('qa.outside',(SELECT user_id::text FROM public.space_members WHERE space_id::text<>current_setting('qa.space') LIMIT 1),true);
SELECT set_config('request.jwt.claim.sub',current_setting('qa.owner'),true);
SET LOCAL ROLE authenticated;
DO $test$
DECLARE me uuid:=current_setting('qa.owner')::uuid;
 peer uuid:=current_setting('qa.peer')::uuid;
 stranger uuid:=current_setting('qa.outside')::uuid;
 couple uuid:=current_setting('qa.space')::uuid;
 personal_id uuid;path text;cnt int;
BEGIN
 IF me IS NULL OR peer IS NULL OR stranger IS NULL THEN RAISE EXCEPTION 'QA pair/outsider fixture missing';END IF;
 path:=me::text||'/'||gen_random_uuid()::text||'.pdf';
 INSERT INTO storage.objects(bucket_id,name,owner_id)
 VALUES('onespace-private-share-in',path,me::text);
 SELECT count(*) INTO cnt FROM storage.objects WHERE bucket_id='onespace-private-share-in' AND name=path;
 IF cnt<>1 THEN RAISE EXCEPTION 'Author cannot inspect own pending personal PDF';END IF;
 INSERT INTO public.items_to_sort(private_space_id,created_by,visibility,title,
   file_path,file_bucket_id,file_name,file_mime,file_size)
 VALUES(me,me,'private','My incoming PDF',path,'onespace-private-share-in',
   'my.pdf','application/pdf',314) RETURNING id INTO personal_id;
 SELECT count(*) INTO cnt FROM public.items_to_sort WHERE id=personal_id;
 IF cnt<>1 THEN RAISE EXCEPTION 'Author cannot see private incoming metadata';END IF;
 PERFORM set_config('request.jwt.claim.sub',peer::text,true);
 SELECT count(*) INTO cnt FROM public.items_to_sort WHERE id=personal_id;
 IF cnt<>0 THEN RAISE EXCEPTION 'Partner sees personal Share-in metadata';END IF;
 SELECT count(*) INTO cnt FROM storage.objects WHERE bucket_id='onespace-private-share-in' AND name=path;
 IF cnt<>0 THEN RAISE EXCEPTION 'Partner sees private incoming PDF';END IF;
 PERFORM set_config('request.jwt.claim.sub',stranger::text,true);
 SELECT count(*) INTO cnt FROM storage.objects WHERE bucket_id='onespace-private-share-in' AND name=path;
 IF cnt<>0 THEN RAISE EXCEPTION 'Outsider sees private incoming PDF';END IF;
 PERFORM set_config('request.jwt.claim.sub',me::text,true);
 BEGIN
  INSERT INTO public.items_to_sort(private_space_id,created_by,visibility,title,
    file_path,file_bucket_id,file_mime,file_size)
  VALUES(me,me,'private','Forged couple attachment',
    me::text||'/'||gen_random_uuid()::text||'.pdf',
    'onespace-share-in','application/pdf',100);
  RAISE EXCEPTION 'BUG: private inbox accepted couple file bucket';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM LIKE 'BUG:%' THEN RAISE; END IF; END;
 BEGIN
  INSERT INTO public.items_to_sort(space_id,created_by,visibility,title,
    file_path,file_bucket_id,file_mime,file_size)
  VALUES(couple,me,'shared','Forged personal bucket',
    me::text||'/'||gen_random_uuid()::text||'.pdf',
    'onespace-private-share-in','application/pdf',100);
  RAISE EXCEPTION 'BUG: shared inbox accepted personal file bucket';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM LIKE 'BUG:%' THEN RAISE; END IF; END;
 BEGIN
  UPDATE public.items_to_sort SET file_bucket_id='onespace-share-in' WHERE id=personal_id;
  RAISE EXCEPTION 'BUG: existing personal attachment moved to couple bucket';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM LIKE 'BUG:%' THEN RAISE; END IF; END;
 BEGIN
  INSERT INTO storage.objects(bucket_id,name,owner_id)
  VALUES('onespace-private-share-in',peer::text||'/'||gen_random_uuid()::text||'.pdf',me::text);
  RAISE EXCEPTION 'BUG: owner uploaded to partner personal folder';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM LIKE 'BUG:%' THEN RAISE; END IF; END;
END $test$;
ROLLBACK;
SELECT 'PASS account-only Share-in file upload/read, partner outsider isolation, cross-bucket and author/path spoof rejections; all rolled back' result;