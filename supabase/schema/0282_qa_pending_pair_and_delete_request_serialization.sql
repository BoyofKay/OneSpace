-- QA ONLY: serialize pair creation, invitation acceptance and a user's
-- account-delete request on the same advisory lock (per user, namespace 5).
-- Prevents a newly accepted pairing racing a just-submitted delete request.
CREATE OR REPLACE FUNCTION private.qa_pending_account_pairing_guard()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $q$
DECLARE ids uuid[]:='{}'::uuid[];uid uuid;creator uuid; old_user uuid;
BEGIN
 IF tg_table_name='spaces' THEN
  ids:=array_append(ids,new.created_by);
  IF tg_op='UPDATE' THEN ids:=array_append(ids,old.created_by);END IF;
 ELSE
  SELECT s.created_by INTO creator FROM public.spaces s WHERE s.id=new.space_id;
  ids:=array_append(ids,creator);
  IF tg_table_name='space_members' THEN
   ids:=array_append(ids,new.user_id);
   IF tg_op='UPDATE' THEN ids:=array_append(ids,old.user_id);END IF;
  ELSE
   ids:=array_append(ids,new.invited_by);
   ids:=array_append(ids,new.accepted_by);
   IF tg_op='UPDATE' THEN
    ids:=array_append(ids,old.invited_by);
    ids:=array_append(ids,old.accepted_by);
   END IF;
  END IF;
  SELECT array_cat(ids,coalesce(array_agg(m.user_id),'{}'::uuid[]))
    INTO ids FROM public.space_members m WHERE m.space_id=new.space_id;
 END IF;
 -- Deterministic ordering prevents two accounts simultaneously pairing each
 -- other from deadlocking. Delete/cancel RPCs lock their own user ID.
 FOR uid IN SELECT DISTINCT x FROM unnest(ids) x
  WHERE x IS NOT NULL ORDER BY x LOOP
  PERFORM pg_advisory_xact_lock(hashtextextended(uid::text,5));
 END LOOP;
 FOR uid IN SELECT DISTINCT x FROM unnest(ids) x
  WHERE x IS NOT NULL LOOP
  IF private.qa_account_pending_delete(uid) THEN
   RAISE EXCEPTION 'Cannot pair or invite while account deletion is pending'
     USING ERRCODE='42501';
  END IF;
 END LOOP;
 RETURN new;
END $q$;
REVOKE ALL ON FUNCTION private.qa_pending_account_pairing_guard()
 FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.request_account_deletion()
RETURNS timestamptz LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $q$
DECLARE me uuid:=auth.uid();due timestamptz;
BEGIN
 IF me IS NULL THEN
  RAISE EXCEPTION 'Sign in to request deletion' USING ERRCODE='42501';
 END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(me::text,5));
 INSERT INTO public.account_deletion_requests(
  user_id,requested_at,purge_after,cancelled_at,completed_at,last_error,processing_at)
 VALUES(me,now(),now()+interval '7 days',NULL,NULL,NULL,NULL)
 ON CONFLICT(user_id) DO UPDATE SET
  requested_at=CASE WHEN account_deletion_requests.cancelled_at IS NULL
     AND account_deletion_requests.completed_at IS NULL
   THEN account_deletion_requests.requested_at ELSE now() END,
  purge_after=CASE WHEN account_deletion_requests.cancelled_at IS NULL
     AND account_deletion_requests.completed_at IS NULL
   THEN account_deletion_requests.purge_after ELSE now()+interval '7 days' END,
  cancelled_at=NULL,last_error=NULL
 WHERE account_deletion_requests.processing_at IS NULL
   AND account_deletion_requests.completed_at IS NULL
 RETURNING purge_after INTO due;
 IF due IS NULL THEN
  RAISE EXCEPTION 'Account deletion cannot be re-requested once finalization begins'
   USING ERRCODE='42501';
 END IF;
 RETURN due;
END $q$;

CREATE OR REPLACE FUNCTION public.cancel_account_deletion()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $q$
DECLARE me uuid:=auth.uid();stopped integer;
BEGIN
 IF me IS NULL THEN
  RAISE EXCEPTION 'Sign in to cancel deletion' USING ERRCODE='42501';
 END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(me::text,5));
 UPDATE public.account_deletion_requests
  SET cancelled_at=now(),last_error=NULL
 WHERE user_id=me AND cancelled_at IS NULL AND completed_at IS NULL
   AND processing_at IS NULL AND purge_after>now();
 GET DIAGNOSTICS stopped=ROW_COUNT;
 IF stopped=0 AND EXISTS(SELECT 1 FROM public.account_deletion_requests
  WHERE user_id=me AND cancelled_at IS NULL AND completed_at IS NULL) THEN
  RAISE EXCEPTION 'The seven-day cancellation window has ended or processing started'
   USING ERRCODE='42501';
 END IF;
END $q$;
-- No new client rights are granted. The account-delete request stays revoked.
