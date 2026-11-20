-- QA ONLY. Account DELETE *after* the 7-day grace may retire the user's
-- historical solo space, distinct from account-owned user_private_spaces.
-- Never use this function for Leave/Remove/Delete Couple. Gate remains OFF.
CREATE OR REPLACE FUNCTION public.qa_retire_due_account_legacy_solo(p_user uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $q$
DECLARE due timestamptz;retired integer;other_member_count integer;
BEGIN
 IF current_user<>'service_role' THEN
  RAISE EXCEPTION 'Service-only old solo space retirement' USING ERRCODE='42501';
 END IF;
 IF NOT EXISTS(SELECT 1 FROM private.qa_account_v2_gate
   WHERE id=1 AND enabled) THEN
  RAISE EXCEPTION 'Account deletion gate closed' USING ERRCODE='42501';
 END IF;
 IF p_user IS NULL THEN RAISE EXCEPTION 'Owner required' USING ERRCODE='22023';END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(p_user::text,1));
 SELECT r.purge_after INTO due FROM public.account_deletion_requests r
 WHERE r.user_id=p_user AND r.cancelled_at IS NULL
  AND r.completed_at IS NULL AND r.processing_at IS NULL
  AND r.purge_after<=now()
 FOR UPDATE;
 IF due IS NULL THEN
  RAISE EXCEPTION 'The full seven-day account deletion grace has not expired'
   USING ERRCODE='42501';
 END IF;
 IF NOT EXISTS(SELECT 1 FROM public.user_private_spaces p
    WHERE p.owner_id=p_user) THEN
  RAISE EXCEPTION 'Account-owned private namespace missing' USING ERRCODE='42501';
 END IF;
 -- Any live relationship must be completed through the separate couple
 -- erasure transaction, protecting the surviving person's private namespace.
 IF EXISTS(SELECT 1 FROM public.space_members m JOIN public.spaces s
     ON s.id=m.space_id
     WHERE m.user_id=p_user AND
       (s.personal_owner IS DISTINCT FROM p_user OR s.created_by<>p_user)) THEN
  RAISE EXCEPTION 'Close the current shared relationship first' USING ERRCODE='42501';
 END IF;
 IF EXISTS(SELECT 1 FROM public.spaces s WHERE s.created_by=p_user
     AND s.personal_owner IS DISTINCT FROM p_user) THEN
  RAISE EXCEPTION 'Creator-owned shared space requires separate couple closure'
    USING ERRCODE='42501';
 END IF;
 SELECT count(*) INTO other_member_count
 FROM public.space_members m JOIN public.spaces s ON s.id=m.space_id
 WHERE s.personal_owner=p_user AND s.created_by=p_user
   AND m.user_id<>p_user;
 IF other_member_count<>0 THEN
  RAISE EXCEPTION 'A historical solo space has another member: refuse deletion'
   USING ERRCODE='42501';
 END IF;
 -- Only account-owned legacy solo spaces, NEVER a couple.
 DELETE FROM public.spaces s
 WHERE s.personal_owner=p_user AND s.created_by=p_user
 AND NOT EXISTS(SELECT 1 FROM public.space_members m
   WHERE m.space_id=s.id AND m.user_id<>p_user);
 GET DIAGNOSTICS retired=ROW_COUNT;
 IF NOT EXISTS(SELECT 1 FROM public.user_private_spaces p WHERE p.owner_id=p_user)
 THEN RAISE EXCEPTION 'Private account namespace was unexpectedly affected'
   USING ERRCODE='42501';END IF;
 RETURN jsonb_build_object('retired_legacy_solo_spaces',retired,
  'private_namespace_preserved',true,'auth_user_deleted',false);
END $q$;
REVOKE ALL ON FUNCTION public.qa_retire_due_account_legacy_solo(uuid)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.qa_retire_due_account_legacy_solo(uuid)
 TO service_role;
