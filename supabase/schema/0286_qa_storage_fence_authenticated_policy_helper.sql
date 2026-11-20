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
