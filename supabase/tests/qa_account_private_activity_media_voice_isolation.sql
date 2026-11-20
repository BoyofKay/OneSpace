-- QA rollback: account-owned Activity JPEG + M4A media and comments,
-- partner/outsider denial, old couple bucket spoof rejection.
BEGIN;
SELECT set_config('qa.owner',(SELECT user_id::text FROM public.space_members ORDER BY space_id,user_id LIMIT 1),true);
SELECT set_config('qa.space',(SELECT space_id::text FROM public.space_members WHERE user_id::text=current_setting('qa.owner') LIMIT 1),true);
SELECT set_config('qa.partner',(SELECT user_id::text FROM public.space_members WHERE space_id::text=current_setting('qa.space') AND user_id::text<>current_setting('qa.owner') LIMIT 1),true);
SELECT set_config('qa.outside',(SELECT user_id::text FROM public.space_members WHERE space_id::text<>current_setting('qa.space') LIMIT 1),true);
SELECT set_config('request.jwt.claim.sub',current_setting('qa.owner'),true);
SET LOCAL ROLE authenticated;
DO $qa$
DECLARE me uuid:=current_setting('qa.owner')::uuid;
 partner uuid:=current_setting('qa.partner')::uuid;
 outsider uuid:=current_setting('qa.outside')::uuid;
 a uuid;photo_path text;voice_path text;photo_id uuid;voice_id uuid;cnt int;
BEGIN
 INSERT INTO public.activities(private_space_id,created_by,visibility,title,body)
 VALUES(me,me,'private','My media Activity','Private Activity with picture and voice')
 RETURNING id INTO a;
 photo_path:=a::text||'/'||me::text||'/'||gen_random_uuid()::text||'.jpg';
 voice_path:=a::text||'/'||me::text||'/'||gen_random_uuid()::text||'.m4a';
 INSERT INTO storage.objects(bucket_id,name,owner_id)
 VALUES('onespace-private-activity-media',photo_path,me::text),
       ('onespace-private-activity-voice',voice_path,me::text);
 INSERT INTO public.activity_components(activity_id,created_by,kind,label,payload)
 VALUES(a,me,'image','Private photo',jsonb_build_object('object_path',photo_path,
  'bucket_id','onespace-private-activity-media','mime','image/jpeg'))
 RETURNING id INTO photo_id;
 INSERT INTO public.activity_components(activity_id,created_by,kind,label,payload)
 VALUES(a,me,'voice','Private recording',jsonb_build_object('voice_path',voice_path,
  'bucket_id','onespace-private-activity-voice','voice_seconds',8))
 RETURNING id INTO voice_id;
 INSERT INTO public.activity_comments(activity_id,author_id,body,voice_path,voice_bucket_id,voice_seconds)
 VALUES(a,me,'Voice note',a::text||'/'||me::text||'/'||gen_random_uuid()::text||'.m4a',
 'onespace-private-activity-voice',4);
 SELECT count(*) INTO cnt FROM storage.objects
 WHERE name IN(photo_path,voice_path);
 IF cnt<>2 THEN RAISE EXCEPTION 'Owner cannot open private Activity image and recording';END IF;
 PERFORM set_config('request.jwt.claim.sub',partner::text,true);
 SELECT count(*) INTO cnt FROM storage.objects WHERE name IN(photo_path,voice_path);
 IF cnt<>0 THEN RAISE EXCEPTION 'Partner sees account-owned Activity files';END IF;
 SELECT count(*) INTO cnt FROM public.activity_components WHERE id IN(photo_id,voice_id);
 IF cnt<>0 THEN RAISE EXCEPTION 'Partner can read personal media references';END IF;
 PERFORM set_config('request.jwt.claim.sub',outsider::text,true);
 SELECT count(*) INTO cnt FROM storage.objects WHERE name IN(photo_path,voice_path);
 IF cnt<>0 THEN RAISE EXCEPTION 'Outsider sees account-owned Activity files';END IF;
 PERFORM set_config('request.jwt.claim.sub',me::text,true);
 BEGIN
  INSERT INTO public.activity_components(activity_id,created_by,kind,label,payload)
  VALUES(a,me,'image','Wrong bucket',jsonb_build_object('object_path',
    a::text||'/'||me::text||'/'||gen_random_uuid()::text||'.jpg',
    'bucket_id','onespace-activity-media'));
  RAISE EXCEPTION 'BUG: private image accepted couple bucket';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM LIKE 'BUG:%' THEN RAISE;END IF;END;
 BEGIN
  INSERT INTO public.activity_comments(activity_id,author_id,body,voice_path,voice_seconds)
  VALUES(a,me,'Wrong private voice bucket',a::text||'/'||me::text||'/'||
     gen_random_uuid()::text||'.m4a',8);
  RAISE EXCEPTION 'BUG: personal comment accepted couple voice bucket';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM LIKE 'BUG:%' THEN RAISE;END IF;END;
 BEGIN
  UPDATE public.activity_components SET payload=jsonb_build_object(
    'object_path',a::text||'/'||me::text||'/'||gen_random_uuid()::text||'.jpg',
    'bucket_id','onespace-private-activity-media') WHERE id=photo_id;
  RAISE EXCEPTION 'BUG: personal attachment reassigned to another object';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM LIKE 'BUG:%' THEN RAISE;END IF;END;
END $qa$;
ROLLBACK;
SELECT 'PASS personal Activity image and M4A Storage, partner/outsider isolation and cross-bucket/retarget rejection; rolled back' result;