-- Reconciled 2026-11-20: applied to QA (ugwrpeduzyzrujkizqfo) on 2026-11-20 from
-- qa/activities-memories-two-scope-cutover-20261120:supabase/schema/0277_qa_account_delete_final_readiness_guard.sql (original number 0277). Kept verbatim so the
-- repository replays to the live QA schema. QA only; never apply to Production.
-- QA ONLY. Last read-only check before ANY eventual Auth admin.deleteUser.
-- Critically, Supabase Auth cannot delete a user who still owns Storage
-- objects. This routine removes nothing and NEVER enables finalization.
CREATE OR REPLACE FUNCTION public.qa_account_final_deletion_readiness(p_user uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $q$
DECLARE gate_on boolean; preflight jsonb;remaining_objects bigint;
 path_references bigint;unfinished_private_jobs bigint;unfinished_shared_jobs bigint;
 due boolean; fk_count bigint;member_count bigint;created_count bigint;
 legacy_count bigint;personal_exists boolean;ready boolean;
BEGIN
 IF current_user<>'service_role' THEN
  RAISE EXCEPTION 'Service-only account final readiness' USING ERRCODE='42501';
 END IF;
 IF p_user IS NULL THEN
  RAISE EXCEPTION 'Account user required' USING ERRCODE='22023';
 END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(p_user::text,1));
 SELECT enabled INTO gate_on FROM private.qa_account_v2_gate WHERE id=1;
 -- This gate must be explicitly opened only in isolated QA rollback tests
 -- until finalization and independent device verification are complete.
 IF NOT coalesce(gate_on,false) THEN
  RAISE EXCEPTION 'Account finalization gate closed' USING ERRCODE='42501';
 END IF;
 preflight:=public.qa_account_finalizer_preflight(p_user);
 due:=coalesce((preflight->>'due')::boolean,false);
 member_count:=coalesce((preflight->>'member_spaces')::bigint,0);
 created_count:=coalesce((preflight->>'spaces_created')::bigint,0);
 legacy_count:=coalesce((preflight->>'legacy_couple_private_rows')::bigint,0);
 fk_count:=coalesce((preflight->>'unresolved_no_action_user_references')::bigint,0);
 personal_exists:=coalesce((preflight->>'private_namespace_exists')::boolean,false);

 SELECT count(*) INTO remaining_objects FROM storage.objects o
 WHERE o.owner_id=p_user::text;
 -- A service-created object with NULL/different Storage ownership must
 -- not be silently orphaned when its path still contains the deleted owner.
 SELECT count(*) INTO path_references FROM storage.objects o
 WHERE p_user::text=ANY(storage.foldername(o.name));
 SELECT count(*) INTO unfinished_private_jobs
 FROM public.qa_account_private_media_purge_queue q
 WHERE q.owner_id=p_user AND q.deleted_at IS NULL;
 SELECT count(*) INTO unfinished_shared_jobs
 FROM public.qa_shared_media_purge_queue q
 WHERE q.expected_uploader_id=p_user AND q.deleted_at IS NULL;
 ready:=due AND personal_exists AND member_count=0 AND created_count=0
  AND legacy_count=0 AND fk_count=0
  AND remaining_objects=0 AND path_references=0
  AND unfinished_private_jobs=0 AND unfinished_shared_jobs=0;
 RETURN jsonb_build_object(
  'ready_for_auth_delete',ready,'due',due,
  'private_namespace_exists',personal_exists,
  'remaining_relationship_memberships',member_count,
  'remaining_created_spaces',created_count,
  'legacy_couple_private_rows',legacy_count,
  'unresolved_auth_user_fk_references',fk_count,
  'remaining_storage_objects_owned',remaining_objects,
  'remaining_storage_folder_references',path_references,
  'unfinished_private_file_purges',unfinished_private_jobs,
  'unfinished_shared_file_purges',unfinished_shared_jobs,
  'actual_auth_deletion_not_implemented',true);
END $q$;
REVOKE ALL ON FUNCTION public.qa_account_final_deletion_readiness(uuid)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.qa_account_final_deletion_readiness(uuid)
 TO service_role;
