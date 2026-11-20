-- QA only: due-account media inventory/partner isolation, all writes rollback.
-- Never deletes Auth users or files; disabled service gate only opened locally.
BEGIN;
SELECT set_config('qa.owner',(SELECT user_id::text FROM public.space_members ORDER BY space_id,user_id LIMIT 1),true);
SELECT set_config('qa.peer',(SELECT user_id::text FROM public.space_members
 WHERE space_id=(SELECT space_id FROM public.space_members WHERE user_id::text=current_setting('qa.owner') LIMIT 1)
 AND user_id::text<>current_setting('qa.owner') LIMIT 1),true);
SELECT set_config('qa.space',(SELECT space_id::text FROM public.space_members
 WHERE user_id::text=current_setting('qa.owner') LIMIT 1),true);
INSERT INTO public.account_deletion_requests(user_id,requested_at,purge_after)
VALUES(current_setting('qa.owner')::uuid,now()-interval '8 days',now()-interval '1 day');
INSERT INTO storage.objects(bucket_id,name,owner_id)
VALUES(
 'onespace-private-note-images',
 gen_random_uuid()::text||'/'||current_setting('qa.owner')||'/'||gen_random_uuid()::text||'.jpg',
 current_setting('qa.owner')),
 (
 'onespace-private-share-in',
 current_setting('qa.owner')||'/'||gen_random_uuid()::text||'.pdf',
 current_setting('qa.owner')),
 (
 'onespace-private-note-images',
 gen_random_uuid()::text||'/'||current_setting('qa.peer')||'/'||gen_random_uuid()::text||'.jpg',
 current_setting('qa.peer')),
 (
 'onespace-private-activity-media',
 gen_random_uuid()::text||'/'||current_setting('qa.owner')||'/'||gen_random_uuid()::text||'.jpg',
 current_setting('qa.owner')),
 (
 'onespace-private-activity-voice',
 gen_random_uuid()::text||'/'||current_setting('qa.owner')||'/'||gen_random_uuid()::text||'.m4a',
 current_setting('qa.owner'));
SET LOCAL ROLE authenticated;
DO $client$
BEGIN
 BEGIN
  PERFORM private.qa_inventory_due_private_media(current_setting('qa.owner')::uuid);
  RAISE EXCEPTION 'BUG: authenticated client accessed account purge inventory';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM LIKE 'BUG:%' THEN RAISE;END IF;END;
END $client$;
RESET ROLE;
SET LOCAL ROLE service_role;
DO $closed$
BEGIN
 BEGIN
  PERFORM private.qa_inventory_due_private_media(current_setting('qa.owner')::uuid);
  RAISE EXCEPTION 'BUG: disabled due-account purge gate was bypassed';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM LIKE 'BUG:%' THEN RAISE;END IF;END;
END $closed$;
RESET ROLE;
UPDATE private.qa_account_v2_gate SET enabled=true WHERE id=1;
SET LOCAL ROLE service_role;
DO $allowed$
DECLARE out jsonb;cnt integer;
BEGIN
 out:=private.qa_inventory_due_private_media(current_setting('qa.owner')::uuid);
 IF (out->>'files_queued')::integer<>4 THEN
  RAISE EXCEPTION 'Private file inventory counted partner or missed owner';END IF;
 SELECT count(*) INTO cnt FROM public.qa_account_private_media_purge_queue
 WHERE owner_id=current_setting('qa.peer')::uuid;
 IF cnt<>0 THEN RAISE EXCEPTION 'Partner files included in requester account purge';END IF;
 SELECT count(*) INTO cnt FROM public.qa_account_private_media_purge_queue
 WHERE owner_id=current_setting('qa.owner')::uuid AND deleted_at IS NULL;
 IF cnt<>4 THEN RAISE EXCEPTION 'Account purge queue count mismatch';END IF;
END $allowed$;
ROLLBACK;
SELECT 'PASS due-only account file inventory, service gate, all four seeded personal buckets including Activity photo/voice, partner exclusion and client denial; rolled back' result;