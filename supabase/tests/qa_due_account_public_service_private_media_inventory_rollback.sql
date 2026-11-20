-- QA rollback. Public service RPC never grants authenticated access;
-- requires true due account, no pair or old account-owned solo space.
BEGIN;
SELECT set_config('qa.uid',gen_random_uuid()::text,true);
INSERT INTO auth.users(id,aud,role,email,encrypted_password,email_confirmed_at)
VALUES(current_setting('qa.uid')::uuid,'authenticated','authenticated',
 'qa-media-rpc-'||current_setting('qa.uid')||'@example.invalid','synthetic',now());
SELECT set_config('qa.path',current_setting('qa.uid')||'/1763638800000.png',true);
INSERT INTO storage.objects(bucket_id,name,owner_id)
VALUES('onespace-support',current_setting('qa.path'),current_setting('qa.uid'));
INSERT INTO public.account_deletion_requests(user_id,requested_at,purge_after)
VALUES(current_setting('qa.uid')::uuid,now()-interval '8 days',now()-interval '1 day');
SELECT set_config('request.jwt.claim.sub',current_setting('qa.uid'),true);
SET LOCAL ROLE authenticated;
DO $client$
BEGIN
 BEGIN
  PERFORM public.qa_prepare_due_account_private_media(current_setting('qa.uid')::uuid);
  RAISE EXCEPTION 'BUG: client can queue account deletion files';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM LIKE 'BUG:%' THEN RAISE;END IF;END;
END $client$;
RESET ROLE;
UPDATE private.qa_account_v2_gate SET enabled=true WHERE id=1;
SET LOCAL ROLE service_role;
DO $solo$
DECLARE rejected boolean:=false;
BEGIN
 BEGIN
  PERFORM public.qa_prepare_due_account_private_media(current_setting('qa.uid')::uuid);
 EXCEPTION WHEN OTHERS THEN rejected:=true; END;
 IF NOT rejected THEN RAISE EXCEPTION 'Old solo ownership did not block file inventory';END IF;
 PERFORM public.qa_retire_due_account_legacy_solo(current_setting('qa.uid')::uuid);
END $solo$;
DO $ready$
DECLARE details jsonb; cnt integer;
BEGIN
 details:=public.qa_prepare_due_account_private_media(current_setting('qa.uid')::uuid);
 IF (details->>'files_queued')::integer<>1 THEN
  RAISE EXCEPTION 'Public service wrapper did not queue support image';END IF;
 SELECT count(*) INTO cnt FROM public.qa_account_private_media_purge_queue
 WHERE owner_id=current_setting('qa.uid')::uuid AND bucket_id='onespace-support'
  AND object_path=current_setting('qa.path') AND deleted_at IS NULL;
 IF cnt<>1 THEN RAISE EXCEPTION 'Service queue audit is missing exact owner/path';END IF;
END $ready$;
ROLLBACK;
SELECT 'PASS service-only due-account media inventory denies clients/solo owner and queues exactly one owned support screenshot after retirement; rolled back' result;