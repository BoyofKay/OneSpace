-- Reconciled 2026-11-20: applied to QA (ugwrpeduzyzrujkizqfo) on 2026-11-20 from
-- qa/activities-memories-two-scope-cutover-20261120:supabase/schema/0286_qa_storage_fence_authenticated_policy_helper.sql (original number 0286). Kept verbatim so the
-- repository replays to the live QA schema. QA only; never apply to Production.
-- QA: Storage RLS evaluates this helper as an authenticated session.
-- It must have EXECUTE privileges, but cannot be used to probe or change
-- another account's deletion status. The private schema is not exposed to
-- the public PostgREST API.
CREATE OR REPLACE FUNCTION private.qa_account_storage_upload_allowed(p_uid uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $q$
 SELECT p_uid IS NOT NULL
  AND p_uid=auth.uid()
  AND NOT EXISTS(
   SELECT 1 FROM public.account_deletion_requests r
   WHERE r.user_id=p_uid AND r.cancelled_at IS NULL AND r.completed_at IS NULL
    AND r.purge_after<=now()
  );
$q$;
REVOKE ALL ON FUNCTION private.qa_account_storage_upload_allowed(uuid)
 FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION private.qa_account_storage_upload_allowed(uuid)
 TO authenticated;
