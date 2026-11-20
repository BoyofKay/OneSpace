-- QA: public/Data API entry point for the trusted service to inventory
-- the due account's OWN media. This safely exposes the already-implemented
-- private function without publishing private schema to client REST.
CREATE OR REPLACE FUNCTION public.qa_prepare_due_account_private_media(p_user uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $q$
BEGIN
 IF current_user<>'service_role' THEN
  RAISE EXCEPTION 'Only service may prepare account media cleanup'
   USING ERRCODE='42501';
 END IF;
 IF p_user IS NULL THEN RAISE EXCEPTION 'Owner required' USING ERRCODE='22023';END IF;
 -- Account must already be disconnected from every couple, including stale
 -- creator-only shared spaces; legacy solo should also be retired first.
 IF EXISTS(SELECT 1 FROM public.space_members m WHERE m.user_id=p_user)
  OR EXISTS(SELECT 1 FROM public.spaces s WHERE s.created_by=p_user) THEN
  RAISE EXCEPTION 'Close relationships and retire solo spaces first'
   USING ERRCODE='42501';
 END IF;
 RETURN private.qa_inventory_due_private_media(p_user);
END $q$;
REVOKE ALL ON FUNCTION public.qa_prepare_due_account_private_media(uuid)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.qa_prepare_due_account_private_media(uuid)
 TO service_role;
