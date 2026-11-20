-- QA rollback: pending deletion stops new relationships/invitations,
-- and an explicit cancellation restores eligibility. No real account changed.
BEGIN;
SELECT set_config('qa.owner',(SELECT m.user_id::text FROM public.space_members m
 JOIN public.spaces s ON s.id=m.space_id
 WHERE s.personal_owner IS NULL ORDER BY m.space_id,m.user_id LIMIT 1),true);
SELECT set_config('qa.space',(SELECT m.space_id::text FROM public.space_members m
 WHERE m.user_id::text=current_setting('qa.owner') AND
 EXISTS(SELECT 1 FROM public.spaces s WHERE s.id=m.space_id AND s.personal_owner IS NULL)
 LIMIT 1),true);
SELECT set_config('qa.outside',(SELECT p.owner_id::text FROM public.user_private_spaces p
 WHERE NOT EXISTS(SELECT 1 FROM public.space_members m
 WHERE m.user_id=p.owner_id AND m.space_id=current_setting('qa.space')::uuid)
 ORDER BY p.owner_id LIMIT 1),true);
INSERT INTO public.account_deletion_requests(user_id,requested_at,purge_after)
VALUES(current_setting('qa.owner')::uuid,now(),now()+interval '7 days');
DO $blocked$
BEGIN
 IF NOT private.qa_account_pending_delete(current_setting('qa.owner')::uuid) THEN
  RAISE EXCEPTION 'Pending deletion not detected';END IF;
 BEGIN
  INSERT INTO public.spaces(name,created_by)
  VALUES('QA should deny new couple',current_setting('qa.owner')::uuid);
  RAISE EXCEPTION 'BUG: pending account created new space';
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM LIKE 'BUG:%' OR SQLERRM NOT LIKE '%deletion is pending%' THEN RAISE;END IF;
 END;
 BEGIN
  INSERT INTO public.space_members(space_id,user_id)
  VALUES(current_setting('qa.space')::uuid,current_setting('qa.outside')::uuid);
  RAISE EXCEPTION 'BUG: pending member space accepted outsider';
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM LIKE 'BUG:%' OR SQLERRM NOT LIKE '%deletion is pending%' THEN RAISE;END IF;
 END;
 BEGIN
  INSERT INTO public.space_invitations(space_id,invited_by,token,expires_at)
  VALUES(current_setting('qa.space')::uuid,current_setting('qa.owner')::uuid,
    gen_random_uuid()::text,now()+interval '1 day');
  RAISE EXCEPTION 'BUG: pending inviter sent invitation';
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM LIKE 'BUG:%' OR SQLERRM NOT LIKE '%deletion is pending%' THEN RAISE;END IF;
 END;
END $blocked$;
UPDATE public.account_deletion_requests SET cancelled_at=now()
 WHERE user_id=current_setting('qa.owner')::uuid;
DO $cancel$
DECLARE n integer;
BEGIN
 IF private.qa_account_pending_delete(current_setting('qa.owner')::uuid) THEN
  RAISE EXCEPTION 'Cancelled account still frozen';END IF;
 INSERT INTO public.spaces(name,created_by)
 VALUES('QA space after cancellation',current_setting('qa.owner')::uuid);
 SELECT count(*) INTO n FROM public.spaces WHERE
  created_by=current_setting('qa.owner')::uuid
  AND name='QA space after cancellation';
 IF n<>1 THEN RAISE EXCEPTION 'Cancellation did not restore space creation';END IF;
END $cancel$;
ROLLBACK;
SELECT 'PASS pending account cannot create pairs/invites or accept new members, cancellation restores eligibility; all rolled back' result;