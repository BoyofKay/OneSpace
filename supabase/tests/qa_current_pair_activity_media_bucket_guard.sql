-- QA rollback: old couple Activity buckets are only for an active two-member
-- relationship. Personal Activity upload into shared bucket must be impossible.
BEGIN;
SELECT set_config('qa.owner',(SELECT user_id::text FROM public.space_members ORDER BY space_id,user_id LIMIT 1),true);
SELECT set_config('qa.space',(SELECT space_id::text FROM public.space_members WHERE user_id::text=current_setting('qa.owner') LIMIT 1),true);
SELECT set_config('qa.partner',(SELECT user_id::text FROM public.space_members WHERE space_id::text=current_setting('qa.space') AND user_id::text<>current_setting('qa.owner') LIMIT 1),true);
SELECT set_config('qa.outsider',(SELECT user_id::text FROM public.space_members WHERE space_id::text<>current_setting('qa.space') LIMIT 1),true);
SELECT set_config('request.jwt.claim.sub',current_setting('qa.owner'),true);
SET LOCAL ROLE authenticated;
DO $first$
DECLARE a uuid;shared_a uuid;me uuid:=current_setting('qa.owner')::uuid;
 path text;n integer;
BEGIN
 INSERT INTO public.activities(private_space_id,created_by,visibility,title)
 VALUES(me,me,'private','Personal bucket guard') RETURNING id INTO a;
 BEGIN
  INSERT INTO storage.objects(bucket_id,name,owner_id)
  VALUES('onespace-activity-media',a::text||'/'||me::text||'/'||gen_random_uuid()::text||'.jpg',
    me::text);
  RAISE EXCEPTION 'BUG: personal Activity uploaded into old shared file bucket';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM LIKE 'BUG:%' THEN RAISE; END IF; END;
 INSERT INTO public.activities(space_id,created_by,visibility,title)
 VALUES(current_setting('qa.space')::uuid,me,'shared','Shared bucket allowed')
 RETURNING id INTO shared_a;
 path:=shared_a::text||'/'||me::text||'/'||gen_random_uuid()::text||'.jpg';
 INSERT INTO storage.objects(bucket_id,name,owner_id)
 VALUES('onespace-activity-media',path,me::text);
 PERFORM set_config('qa.shared_media',path,true);
 SELECT count(*) INTO n FROM storage.objects
 WHERE bucket_id='onespace-activity-media' AND name=path;
 IF n<>1 THEN RAISE EXCEPTION 'Current pair owner cannot access shared photo';END IF;
 PERFORM set_config('request.jwt.claim.sub',current_setting('qa.partner'),true);
 SELECT count(*) INTO n FROM storage.objects
 WHERE bucket_id='onespace-activity-media' AND name=path;
 IF n<>1 THEN RAISE EXCEPTION 'Current partner cannot see shared photo';END IF;
 PERFORM set_config('request.jwt.claim.sub',current_setting('qa.outsider'),true);
 SELECT count(*) INTO n FROM storage.objects
 WHERE bucket_id='onespace-activity-media' AND name=path;
 IF n<>0 THEN RAISE EXCEPTION 'Outsider reads another couple media';END IF;
END $first$;
RESET ROLE;
-- Deliberately unpair inside a rollback test without deleting the shared root,
-- proving stale links no longer allow either former partner to read file bytes.
DELETE FROM public.space_members WHERE space_id=current_setting('qa.space')::uuid
 AND user_id=current_setting('qa.partner')::uuid;
SET LOCAL ROLE authenticated;
DO $after$
DECLARE n integer;
BEGIN
 PERFORM set_config('request.jwt.claim.sub',current_setting('qa.owner'),true);
 SELECT count(*) INTO n FROM storage.objects
 WHERE bucket_id='onespace-activity-media' AND name=current_setting('qa.shared_media');
 IF n<>0 THEN RAISE EXCEPTION 'Unpaired former owner reads shared media';END IF;
 PERFORM set_config('request.jwt.claim.sub',current_setting('qa.partner'),true);
 SELECT count(*) INTO n FROM storage.objects
 WHERE bucket_id='onespace-activity-media' AND name=current_setting('qa.shared_media');
 IF n<>0 THEN RAISE EXCEPTION 'Former partner reads past couple media';END IF;
END $after$;
ROLLBACK;
SELECT 'PASS shared media only during active pair, personal Activity cannot upload into couple bucket, former partners denied; rolled back' result;