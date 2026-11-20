-- QA ROLLBACK. The final readiness API MUST deny users, require its
-- service gate and block a due account with remaining pair / Storage files.
BEGIN;
SELECT set_config('qa.owner',(SELECT p.owner_id::text FROM public.user_private_spaces p
 WHERE EXISTS(SELECT 1 FROM public.space_members m WHERE m.user_id=p.owner_id)
 ORDER BY p.owner_id LIMIT 1),true);
INSERT INTO public.account_deletion_requests(user_id,requested_at,purge_after)
VALUES(current_setting('qa.owner')::uuid,now()-interval '8 days',now()-interval '1 day');
SELECT set_config('request.jwt.claim.sub',current_setting('qa.owner'),true);
SET LOCAL ROLE authenticated;
DO $user$
BEGIN
 BEGIN
  PERFORM public.qa_account_final_deletion_readiness(current_setting('qa.owner')::uuid);
  RAISE EXCEPTION 'BUG: regular user ran privileged deletion preflight';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM LIKE 'BUG:%' THEN RAISE;END IF;END;
END $user$;
RESET ROLE;
SET LOCAL ROLE service_role;
DO $closed$
BEGIN
 BEGIN
  PERFORM public.qa_account_final_deletion_readiness(current_setting('qa.owner')::uuid);
  RAISE EXCEPTION 'BUG: final readiness bypassed service gate';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM LIKE 'BUG:%' THEN RAISE;END IF;END;
END $closed$;
RESET ROLE;
UPDATE private.qa_account_v2_gate SET enabled=true WHERE id=1;
SET LOCAL ROLE service_role;
DO $paired$
DECLARE status jsonb; n integer;
BEGIN
 status:=public.qa_account_final_deletion_readiness(current_setting('qa.owner')::uuid);
 IF status->>'ready_for_auth_delete'<>'false' OR status->>'due'<>'true'
 OR (status->>'remaining_relationship_memberships')::integer<1 THEN
  RAISE EXCEPTION 'Due account with current relationship falsely approved';
 END IF;
END $paired$;
RESET ROLE;
SELECT set_config('qa.path',gen_random_uuid()::text||'/'||
 current_setting('qa.owner')||'/'||gen_random_uuid()::text||'.jpg',true);
INSERT INTO storage.objects(bucket_id,name,owner_id)
VALUES('onespace-private-activity-media',current_setting('qa.path'),current_setting('qa.owner'));
SET LOCAL ROLE service_role;
DO $file$
DECLARE status jsonb;
BEGIN
 status:=public.qa_account_final_deletion_readiness(current_setting('qa.owner')::uuid);
 IF (status->>'remaining_storage_objects_owned')::integer<>1 OR
    (status->>'remaining_storage_folder_references')::integer<>1 OR
    status->>'ready_for_auth_delete'<>'false' THEN
   RAISE EXCEPTION 'Auth delete readiness ignored existing owner file';
 END IF;
END $file$;
ROLLBACK;
SELECT 'PASS service-only account delete readiness requires closed gate, no active pair and zero owned/path files; no user/data deletion, rollback' result;