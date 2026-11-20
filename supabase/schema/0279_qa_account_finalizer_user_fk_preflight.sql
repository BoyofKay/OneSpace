-- Reconciled 2026-11-20: applied to QA (ugwrpeduzyzrujkizqfo) on 2026-11-20 from
-- qa/activities-memories-two-scope-cutover-20261120:supabase/schema/0272_qa_account_finalizer_user_fk_preflight.sql (original number 0272). Kept verbatim so the
-- repository replays to the live QA schema. QA only; never apply to Production.
-- QA ONLY: non-destructive finalizer preflight. No Auth-user deletion.
-- This is a read-only service-only count of scope, FK and grace blockers.
CREATE OR REPLACE FUNCTION public.qa_account_finalizer_preflight(p_user uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $q$
DECLARE due timestamptz;valid_request boolean:=false;
 member_spaces integer;created_spaces integer;foreign_member_spaces integer;
 private_namespace_exists boolean; legacy_private bigint;
 child_user_refs bigint:=0; extra_refs jsonb:='{}'::jsonb;r record;n bigint;
BEGIN
 IF current_user<>'service_role' THEN
  RAISE EXCEPTION 'Service-only account finalizer preflight' USING ERRCODE='42501';
 END IF;
 IF p_user IS NULL THEN RAISE EXCEPTION 'User required' USING ERRCODE='22023';END IF;
 SELECT purge_after,purge_after<=now() AND cancelled_at IS NULL
   AND completed_at IS NULL AND processing_at IS NULL
 INTO due,valid_request
 FROM public.account_deletion_requests WHERE user_id=p_user;
 SELECT count(*) INTO member_spaces FROM public.space_members WHERE user_id=p_user;
 SELECT count(*) INTO created_spaces FROM public.spaces WHERE created_by=p_user;
 SELECT count(*) INTO foreign_member_spaces FROM public.spaces s
 WHERE s.created_by=p_user AND EXISTS(
  SELECT 1 FROM public.space_members m
  WHERE m.space_id=s.id AND m.user_id<>p_user);
 SELECT EXISTS(SELECT 1 FROM public.user_private_spaces
   WHERE owner_id=p_user) INTO private_namespace_exists;
 -- If stale clients left personal rows stored in a couple, fail closed.
 SELECT coalesce(sum(v.n),0) INTO legacy_private FROM (
 SELECT count(*) n FROM public.notes WHERE created_by=p_user
   AND visibility='private' AND private_space_id IS NULL AND space_id IS NOT NULL
 UNION ALL
 SELECT count(*) FROM public.tasks WHERE created_by=p_user
   AND visibility='private' AND private_space_id IS NULL AND space_id IS NOT NULL
 UNION ALL
 SELECT count(*) FROM public.activities WHERE created_by=p_user
   AND visibility='private' AND private_space_id IS NULL AND space_id IS NOT NULL
 UNION ALL
 SELECT count(*) FROM public.memories WHERE created_by=p_user
   AND visibility='private' AND private_space_id IS NULL AND space_id IS NOT NULL
 ) v;
 FOR r IN
  SELECT c.conrelid::regclass::text tab,a.attname col
  FROM pg_constraint c JOIN pg_class cl ON cl.oid=c.conrelid
  JOIN pg_namespace ns ON ns.oid=cl.relnamespace
  JOIN pg_attribute a ON a.attrelid=c.conrelid AND a.attnum=c.conkey[1]
  WHERE c.contype='f' AND c.confrelid='auth.users'::regclass
   AND c.confdeltype IN ('a','r') AND cardinality(c.conkey)=1
   AND ns.nspname='public'
  ORDER BY c.conrelid::regclass::text,a.attname
 LOOP
  EXECUTE format('SELECT count(*) FROM %s WHERE %I=$1',r.tab,r.col)
   INTO n USING p_user;
  IF n>0 THEN
   child_user_refs:=child_user_refs+n;
   extra_refs:=extra_refs||jsonb_build_object(r.tab||'.'||r.col,n);
  END IF;
 END LOOP;
 RETURN jsonb_build_object(
 'due',coalesce(valid_request,false),'deadline',due,
 'private_namespace_exists',private_namespace_exists,
 'member_spaces',member_spaces,'spaces_created',created_spaces,
 'created_spaces_with_other_members',foreign_member_spaces,
 'legacy_couple_private_rows',legacy_private,
 'unresolved_no_action_user_references',child_user_refs,
 'unresolved_reference_groups',extra_refs,
 'ready_for_destructive_finalization',false,
 'blocked_reason','Service finalization intentionally disabled; cleanup and Storage/Auth procedures pending');
END $q$;
REVOKE ALL ON FUNCTION public.qa_account_finalizer_preflight(uuid)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.qa_account_finalizer_preflight(uuid) TO service_role;

-- Retired QA archive progress cannot keep an otherwise fully deleted account
-- alive merely because it was a recipient of a deprecated export record.
-- Historical account rows remain untouched by this schema change.
ALTER TABLE public.qa_archive_job_progress
 DROP CONSTRAINT IF EXISTS qa_archive_job_progress_recipient_id_fkey;
ALTER TABLE public.qa_archive_job_progress
 ADD CONSTRAINT qa_archive_job_progress_recipient_id_fkey
 FOREIGN KEY(recipient_id) REFERENCES auth.users(id)
 ON DELETE CASCADE NOT VALID;
