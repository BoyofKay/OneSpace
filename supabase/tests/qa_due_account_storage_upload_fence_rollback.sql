-- QA rollback: uploads are allowed in seven-day grace, denied once due,
-- and restored by timely cancelled deletion; no real accounts affected.
BEGIN;
SELECT set_config('qa.fake',gen_random_uuid()::text,true);
INSERT INTO auth.users(id,aud,role,email,encrypted_password,email_confirmed_at)
VALUES(current_setting('qa.fake')::uuid,'authenticated','authenticated',
 'qa-storage-fence-'||current_setting('qa.fake')||'@example.invalid','synthetic',now());
SELECT set_config('request.jwt.claim.sub',current_setting('qa.fake'),true);
SET LOCAL ROLE authenticated;
INSERT INTO public.activities(private_space_id,created_by,visibility,title)
VALUES(current_setting('qa.fake')::uuid,current_setting('qa.fake')::uuid,
 'private','Synthetic media during deletion grace');
RESET ROLE;
SELECT set_config('qa.activity',(SELECT id::text FROM public.activities
 WHERE private_space_id=current_setting('qa.fake')::uuid
 AND title='Synthetic media during deletion grace' LIMIT 1),true);
INSERT INTO public.account_deletion_requests(user_id,requested_at,purge_after)
VALUES(current_setting('qa.fake')::uuid,now(),now()+interval '7 days');
SELECT set_config('request.jwt.claim.sub',current_setting('qa.fake'),true);
SET LOCAL ROLE authenticated;
DO $grace$
DECLARE path text;
BEGIN
 IF NOT private.qa_account_storage_upload_allowed(current_setting('qa.fake')::uuid) THEN
  RAISE EXCEPTION 'Seven-day grace wrongly freezes uploads';END IF;
 path:=current_setting('qa.activity')||'/'||current_setting('qa.fake')||
  '/'||gen_random_uuid()::text||'.jpg';
 INSERT INTO storage.objects(bucket_id,name,owner_id)
 VALUES('onespace-private-activity-media',path,current_setting('qa.fake'));
END $grace$;
RESET ROLE;
UPDATE public.account_deletion_requests SET requested_at=now()-interval '8 days',
 purge_after=now()-interval '1 day' WHERE user_id=current_setting('qa.fake')::uuid;
SET LOCAL ROLE authenticated;
DO $due$
DECLARE path text;did_reject boolean:=false;
BEGIN
 IF private.qa_account_storage_upload_allowed(current_setting('qa.fake')::uuid) THEN
  RAISE EXCEPTION 'Due deletion account still allowed to upload';END IF;
 path:=current_setting('qa.activity')||'/'||current_setting('qa.fake')||
  '/'||gen_random_uuid()::text||'.jpg';
 BEGIN
  INSERT INTO storage.objects(bucket_id,name,owner_id)
  VALUES('onespace-private-activity-media',path,current_setting('qa.fake'));
 EXCEPTION WHEN OTHERS THEN did_reject:=true;
 END;
 IF NOT did_reject THEN RAISE EXCEPTION 'BUG: expired account wrote a new Storage file';END IF;
END $due$;
RESET ROLE;
UPDATE public.account_deletion_requests SET cancelled_at=now(),
 purge_after=now()+interval '7 days' WHERE user_id=current_setting('qa.fake')::uuid;
SET LOCAL ROLE authenticated;
DO $cancel$
DECLARE path text;
BEGIN
 IF NOT private.qa_account_storage_upload_allowed(current_setting('qa.fake')::uuid) THEN
  RAISE EXCEPTION 'Cancellation did not restore Storage uploads';END IF;
 path:=current_setting('qa.activity')||'/'||current_setting('qa.fake')||
  '/'||gen_random_uuid()::text||'.jpg';
 INSERT INTO storage.objects(bucket_id,name,owner_id)
 VALUES('onespace-private-activity-media',path,current_setting('qa.fake'));
END $cancel$;
ROLLBACK;
SELECT 'PASS due account denied new Storage uploads, grace allowed, cancellation restored access; synthetic rollback' result;