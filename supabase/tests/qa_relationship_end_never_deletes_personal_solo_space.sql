-- QA rollback: user may never use Remove/Leave/Delete couple action
-- to erase a legacy account-created solo space, even if it is theirs.
BEGIN;
SELECT set_config('qa.user',(SELECT s.personal_owner::text FROM public.spaces s
 WHERE s.personal_owner IS NOT NULL AND s.created_by=s.personal_owner
 ORDER BY s.id LIMIT 1),true);
SELECT set_config('qa.solo',(SELECT s.id::text FROM public.spaces s
 WHERE s.personal_owner::text=current_setting('qa.user')
   AND s.created_by=s.personal_owner LIMIT 1),true);
GRANT USAGE ON SCHEMA private TO authenticated;
GRANT EXECUTE ON FUNCTION private.qa_close_relationship_v2(uuid,text,text)
 TO authenticated;
UPDATE private.qa_relationship_v2_gate SET enabled=true WHERE id=1;
SELECT set_config('request.jwt.claim.sub',current_setting('qa.user'),true);
SET LOCAL ROLE authenticated;
DO $deny$
DECLARE action text; rejected boolean; n integer;
BEGIN
 FOR action IN SELECT unnest(ARRAY['remove_partner','leave_space','delete_space']) LOOP
  rejected:=false;
  BEGIN
   PERFORM private.qa_close_relationship_v2(
    current_setting('qa.solo')::uuid,action,'DELETE SHARED CONTENT');
  EXCEPTION WHEN OTHERS THEN
   rejected:=SQLERRM LIKE '%Personal solo spaces cannot be removed%';
  END;
  IF NOT rejected THEN RAISE EXCEPTION 'BUG: % could remove account solo space',action;END IF;
 END LOOP;
 SELECT count(*) INTO n FROM public.spaces
 WHERE id=current_setting('qa.solo')::uuid
 AND personal_owner=current_setting('qa.user')::uuid;
 IF n<>1 THEN RAISE EXCEPTION 'Account solo space was lost';END IF;
 SELECT count(*) INTO n FROM public.user_private_spaces
 WHERE owner_id=current_setting('qa.user')::uuid;
 IF n<>1 THEN RAISE EXCEPTION 'Permanent user-private namespace was lost';END IF;
END $deny$;
ROLLBACK;
SELECT 'PASS all three couple-ending actions deny personal solo space deletion; both account spaces preserved; rolled back' result;