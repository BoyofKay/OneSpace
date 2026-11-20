-- Reconciled 2026-11-20: applied to QA (ugwrpeduzyzrujkizqfo) on 2026-11-20 from
-- qa/activities-memories-two-scope-cutover-20261120:supabase/schema/0296_qa_account_deletion_request_facade_disabled.sql (original number 0296). Kept verbatim so the
-- repository replays to the live QA schema. QA only; never apply to Production.
-- QA only: account deletion scheduling is not exposed until the entire
-- seven-day physical Storage + Auth Admin workflow has passed acceptance.
-- Existing public.request_account_deletion remains revoked to clients.
CREATE OR REPLACE FUNCTION public.qa_request_account_deletion()
RETURNS timestamptz LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $q$
DECLARE me uuid:=auth.uid();
BEGIN
 IF me IS NULL OR NOT EXISTS(SELECT 1 FROM auth.users WHERE id=me) THEN
  RAISE EXCEPTION 'Existing signed-in account required'
   USING ERRCODE='42501';
 END IF;
 IF NOT EXISTS(SELECT 1 FROM private.qa_account_v2_gate
   WHERE id=1 AND enabled) THEN
  RAISE EXCEPTION 'Account deletion remains unavailable'
   USING ERRCODE='42501';
 END IF;
 RETURN public.request_account_deletion();
END $q$;
REVOKE ALL ON FUNCTION public.qa_request_account_deletion()
 FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.qa_request_account_deletion() TO authenticated;
