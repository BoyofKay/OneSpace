-- Reconciled 2026-11-20: applied to QA (ugwrpeduzyzrujkizqfo) on 2026-11-20 from
-- qa/activities-memories-two-scope-cutover-20261120:supabase/schema/0285_qa_due_account_storage_upload_fence.sql (original number 0285). Kept verbatim so the
-- repository replays to the live QA schema. QA only; never apply to Production.
-- QA: once a 7-day account-deletion request becomes irrevocably due,
-- block ALL new authenticated Storage uploads/replacements by that account.
-- This closes the race between worker file-inventory, final readiness and
-- Supabase Auth Admin deleteUser. Does not block legitimate app usage while
-- the seven-day grace is still open; cancellation restores access.
CREATE OR REPLACE FUNCTION private.qa_account_storage_upload_allowed(p_uid uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $q$
 SELECT p_uid IS NOT NULL AND NOT EXISTS(
  SELECT 1 FROM public.account_deletion_requests r
  WHERE r.user_id=p_uid AND r.cancelled_at IS NULL AND r.completed_at IS NULL
   AND r.purge_after<=now()
 );
$q$;
REVOKE ALL ON FUNCTION private.qa_account_storage_upload_allowed(uuid)
 FROM PUBLIC,anon,authenticated;

DROP POLICY IF EXISTS "QA due account cannot upload any Storage files" ON storage.objects;
CREATE POLICY "QA due account cannot upload any Storage files"
 ON storage.objects AS RESTRICTIVE FOR INSERT TO authenticated
 WITH CHECK(private.qa_account_storage_upload_allowed((SELECT auth.uid())));

DROP POLICY IF EXISTS "QA due account cannot replace Storage files" ON storage.objects;
CREATE POLICY "QA due account cannot replace Storage files"
 ON storage.objects AS RESTRICTIVE FOR UPDATE TO authenticated
 USING(private.qa_account_storage_upload_allowed((SELECT auth.uid())))
 WITH CHECK(private.qa_account_storage_upload_allowed((SELECT auth.uid())));
