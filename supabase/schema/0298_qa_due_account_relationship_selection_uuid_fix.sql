-- Reconciled 2026-11-20: applied to QA (ugwrpeduzyzrujkizqfo) on 2026-11-20 from
-- qa/activities-memories-two-scope-cutover-20261120:supabase/schema/0291_qa_due_account_relationship_selection_uuid_fix.sql (original number 0291). Kept verbatim so the
-- repository replays to the live QA schema. QA only; never apply to Production.
-- QA: PostgreSQL has no aggregate MIN(uuid); use array_agg and refuse
-- ambiguous multiple relationships before invoking destructive transaction.
CREATE OR REPLACE FUNCTION public.qa_due_account_close_current_relationship(p_user uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $q$
DECLARE due_date timestamptz;sp uuid;owner_id uuid;num_pairs integer;
 prev_claim text:=current_setting('request.jwt.claim.sub',true);
 action_name text;result jsonb;
BEGIN
 IF current_user<>'service_role' THEN
  RAISE EXCEPTION 'Only the service may close an overdue account relationship'
   USING ERRCODE='42501';
 END IF;
 IF p_user IS NULL THEN
  RAISE EXCEPTION 'User id required' USING ERRCODE='22023';
 END IF;
 IF NOT EXISTS(SELECT 1 FROM private.qa_account_v2_gate
  WHERE id=1 AND enabled) OR NOT EXISTS(
  SELECT 1 FROM private.qa_relationship_v2_gate WHERE id=1 AND enabled) THEN
  RAISE EXCEPTION 'Due account relationship closure is not enabled'
    USING ERRCODE='42501';
 END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(p_user::text,5));
 SELECT r.purge_after INTO due_date
 FROM public.account_deletion_requests r
 WHERE r.user_id=p_user AND r.cancelled_at IS NULL
   AND r.completed_at IS NULL AND r.processing_at IS NULL
   AND r.purge_after<=now()
 FOR UPDATE;
 IF due_date IS NULL THEN
  RAISE EXCEPTION 'Cannot close a relationship during the cancellable grace'
    USING ERRCODE='42501';
 END IF;
 IF NOT EXISTS(SELECT 1 FROM public.user_private_spaces p
     WHERE p.owner_id=p_user) THEN
  RAISE EXCEPTION 'Due account private namespace missing'
    USING ERRCODE='42501';
 END IF;
 SELECT count(*),(array_agg(s.id))[1],(array_agg(s.created_by))[1] INTO num_pairs,sp,owner_id
 FROM public.space_members m JOIN public.spaces s ON s.id=m.space_id
 WHERE m.user_id=p_user AND s.personal_owner IS NULL;
 IF num_pairs>1 THEN
  RAISE EXCEPTION 'Multiple relationships need manual reconciliation'
    USING ERRCODE='42501';
 END IF;
 IF num_pairs=0 THEN
  RETURN jsonb_build_object('status','already_unpaired',
    'shared_deleted',false,'private_namespace_preserved',true);
 END IF;
 action_name:=CASE WHEN owner_id=p_user THEN 'delete_space'
  ELSE 'leave_space' END;
 -- The SECURITY DEFINER relationship function already validates that the
 -- actor is the signed-in owner/invited partner, the exact current pair,
 -- deletion phrase, and *all* account-private root row count preservation.
 PERFORM set_config('request.jwt.claim.sub',p_user::text,true);
 result:=private.qa_close_relationship_v2(
  sp,action_name,'DELETE SHARED CONTENT');
 PERFORM set_config('request.jwt.claim.sub',coalesce(prev_claim,''),true);
 IF EXISTS(SELECT 1 FROM public.space_members m WHERE m.user_id=p_user
     AND m.space_id=sp) OR
  NOT EXISTS(SELECT 1 FROM public.user_private_spaces p
     WHERE p.owner_id=p_user) THEN
  RAISE EXCEPTION 'Relationship close failed to unpair or preserve private data'
    USING ERRCODE='42501';
 END IF;
 RETURN result||jsonb_build_object('due_user_id',p_user,
  'closed_on_behalf_of_due_account',true);
END $q$;

REVOKE ALL ON FUNCTION public.qa_due_account_close_current_relationship(uuid)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.qa_due_account_close_current_relationship(uuid)
 TO service_role;
