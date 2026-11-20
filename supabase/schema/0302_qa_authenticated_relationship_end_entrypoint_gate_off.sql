-- Reconciled 2026-11-20: applied to QA (ugwrpeduzyzrujkizqfo) on 2026-11-20 from
-- qa/activities-memories-two-scope-cutover-20261120:supabase/schema/0295_qa_authenticated_relationship_end_entrypoint_gate_off.sql (original number 0295). Kept verbatim so the
-- repository replays to the live QA schema. QA only; never apply to Production.
-- QA-only authenticated entrypoint for irreversible couple separation.
-- The substantive SECURITY DEFINER private transaction validates actor,
-- ownership, exact current pair, permanent private spaces and typed warning.
-- This public facade grants no bypass while the DB gate remains OFF.
CREATE OR REPLACE FUNCTION public.qa_end_current_relationship(
 p_space uuid,p_action text,p_confirmation text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $q$
DECLARE me uuid:=auth.uid();
BEGIN
 IF me IS NULL OR p_space IS NULL THEN
  RAISE EXCEPTION 'Authenticated existing relationship required' USING ERRCODE='42501';
 END IF;
 IF p_action NOT IN('remove_partner','leave_space','delete_space')
  OR p_confirmation IS DISTINCT FROM 'DELETE SHARED CONTENT' THEN
  RAISE EXCEPTION 'Explicit irreversible confirmation required' USING ERRCODE='42501';
 END IF;
 -- Refuse absent-or-synthetic actor. RLS in private transaction also
 -- checks membership and exact owner/guest rules.
 IF NOT EXISTS(SELECT 1 FROM auth.users u WHERE u.id=me) THEN
  RAISE EXCEPTION 'Account no longer exists' USING ERRCODE='42501';
 END IF;
 RETURN private.qa_close_relationship_v2(p_space,p_action,p_confirmation);
END $q$;
REVOKE ALL ON FUNCTION public.qa_end_current_relationship(uuid,text,text)
 FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.qa_end_current_relationship(uuid,text,text)
 TO authenticated;
