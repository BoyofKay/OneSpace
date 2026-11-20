-- Reconciled 2026-11-20: applied to QA (ugwrpeduzyzrujkizqfo) on 2026-11-20 from
-- qa/activities-memories-two-scope-cutover-20261120:supabase/schema/0257_qa_private_and_current_pair_item_link_scope.sql (original number 0257). Kept verbatim so the
-- repository replays to the live QA schema. QA only; never apply to Production.
-- QA-only link scope gate: links cannot carry a personal ID into the couple
-- or bridge one couple to another. Each endpoint must match BOTH storage IDs.
-- Existing historical links have not been migrated; do not enable deletion yet.
CREATE OR REPLACE FUNCTION private.qa_item_link_endpoint(p_kind text,p_id uuid)
RETURNS TABLE(space_id uuid,private_space_id uuid,visibility text)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path='' AS $f$
SELECT i.space_id,i.private_space_id,i.visibility FROM public.activities i WHERE p_kind='activity' AND i.id=p_id
UNION ALL
SELECT i.space_id,i.private_space_id,i.visibility FROM public.shared_trips i WHERE p_kind='trip' AND i.id=p_id
UNION ALL
SELECT i.space_id,i.private_space_id,i.visibility FROM public.occasion_plans i WHERE p_kind='occasion' AND i.id=p_id
UNION ALL
SELECT i.space_id,i.private_space_id,i.visibility FROM public.shared_experiences i WHERE p_kind='experience' AND i.id=p_id
UNION ALL
SELECT i.space_id,i.private_space_id,i.visibility FROM public.space_events i WHERE p_kind='event' AND i.id=p_id
UNION ALL
SELECT i.space_id,i.private_space_id,i.visibility FROM public.reminders i WHERE p_kind='reminder' AND i.id=p_id
UNION ALL
SELECT i.space_id,i.private_space_id,i.visibility FROM public.tasks i WHERE p_kind='task' AND i.id=p_id
UNION ALL
SELECT i.space_id,i.private_space_id,i.visibility FROM public.notes i WHERE p_kind='note' AND i.id=p_id
UNION ALL
SELECT i.space_id,i.private_space_id,i.visibility FROM public.memories i WHERE p_kind='memory' AND i.id=p_id;
$f$;
REVOKE ALL ON FUNCTION private.qa_item_link_endpoint(text,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION private.qa_item_link_endpoint(text,uuid) TO authenticated;

CREATE OR REPLACE FUNCTION private.qa_item_link_exact_scope(
 p_from_kind text,p_from_id uuid,p_to_kind text,p_to_id uuid,
 p_space_id uuid,p_private_space_id uuid
) RETURNS boolean LANGUAGE sql STABLE SECURITY INVOKER SET search_path='' AS $f$
SELECT
 (
  p_space_id IS NOT NULL AND p_private_space_id IS NULL
  AND private.is_space_member(p_space_id)
  AND (SELECT count(*) FROM public.space_members m WHERE m.space_id=p_space_id)=2
  AND EXISTS(SELECT 1 FROM private.qa_item_link_endpoint(p_from_kind,p_from_id) s
   WHERE s.space_id=p_space_id AND s.private_space_id IS NULL AND s.visibility='shared')
  AND EXISTS(SELECT 1 FROM private.qa_item_link_endpoint(p_to_kind,p_to_id) t
   WHERE t.space_id=p_space_id AND t.private_space_id IS NULL AND t.visibility='shared')
 ) OR (
  p_private_space_id IS NOT NULL AND p_space_id IS NULL
  AND p_private_space_id=(select auth.uid())
  AND EXISTS(SELECT 1 FROM public.user_private_spaces s
    WHERE s.owner_id=p_private_space_id)
  AND EXISTS(SELECT 1 FROM private.qa_item_link_endpoint(p_from_kind,p_from_id) s
   WHERE s.private_space_id=p_private_space_id AND s.space_id IS NULL AND s.visibility='private')
  AND EXISTS(SELECT 1 FROM private.qa_item_link_endpoint(p_to_kind,p_to_id) t
   WHERE t.private_space_id=p_private_space_id AND t.space_id IS NULL AND t.visibility='private')
 );
$f$;
REVOKE ALL ON FUNCTION private.qa_item_link_exact_scope(text,uuid,text,uuid,uuid,uuid)
 FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION private.qa_item_link_exact_scope(text,uuid,text,uuid,uuid,uuid)
 TO authenticated;

ALTER TABLE public.item_links ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "QA read my personal links" ON public.item_links;
CREATE POLICY "QA read my personal links" ON public.item_links FOR SELECT TO authenticated
 USING(private_space_id=(select auth.uid()) AND created_by=(select auth.uid()) AND space_id IS NULL);
DROP POLICY IF EXISTS "QA insert my personal links" ON public.item_links;
CREATE POLICY "QA insert my personal links" ON public.item_links FOR INSERT TO authenticated
 WITH CHECK(private_space_id=(select auth.uid()) AND created_by=(select auth.uid()) AND space_id IS NULL);
DROP POLICY IF EXISTS "QA unlink my personal links" ON public.item_links;
CREATE POLICY "QA unlink my personal links" ON public.item_links FOR UPDATE TO authenticated
 USING(private_space_id=(select auth.uid()) AND created_by=(select auth.uid()) AND space_id IS NULL)
 WITH CHECK(private_space_id=(select auth.uid()) AND created_by=(select auth.uid()) AND space_id IS NULL);
DROP POLICY IF EXISTS "QA link exact owner read" ON public.item_links;
CREATE POLICY "QA link exact owner read" ON public.item_links AS RESTRICTIVE
 FOR SELECT TO authenticated USING(
  private.qa_item_link_exact_scope(from_kind,from_id,to_kind,to_id,space_id,private_space_id));
DROP POLICY IF EXISTS "QA link exact owner insert" ON public.item_links;
CREATE POLICY "QA link exact owner insert" ON public.item_links AS RESTRICTIVE
 FOR INSERT TO authenticated WITH CHECK(
  created_by=(select auth.uid())
  AND private.qa_item_link_exact_scope(from_kind,from_id,to_kind,to_id,space_id,private_space_id));
DROP POLICY IF EXISTS "QA link exact owner update" ON public.item_links;
CREATE POLICY "QA link exact owner update" ON public.item_links AS RESTRICTIVE
 FOR UPDATE TO authenticated
 USING(private.qa_item_link_exact_scope(from_kind,from_id,to_kind,to_id,space_id,private_space_id))
 WITH CHECK(private.qa_item_link_exact_scope(from_kind,from_id,to_kind,to_id,space_id,private_space_id));

-- RLS cannot prevent an authorized caller from changing the identifiers
-- in-place, so reject retargeting independently of the permissive policy.
CREATE OR REPLACE FUNCTION private.qa_link_immutable_endpoints()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $f$
BEGIN
 IF current_user NOT IN ('authenticated','anon') THEN RETURN NEW; END IF;
 IF tg_op='UPDATE' AND (
   old.space_id IS DISTINCT FROM new.space_id OR
   old.private_space_id IS DISTINCT FROM new.private_space_id OR
   old.created_by IS DISTINCT FROM new.created_by OR
   old.from_kind IS DISTINCT FROM new.from_kind OR
   old.from_id IS DISTINCT FROM new.from_id OR
   old.to_kind IS DISTINCT FROM new.to_kind OR
   old.to_id IS DISTINCT FROM new.to_id OR
   old.created_at IS DISTINCT FROM new.created_at OR
   old.id IS DISTINCT FROM new.id
 ) THEN
   RAISE EXCEPTION 'Links cannot change owners or endpoints in place'
     USING ERRCODE='42501';
 END IF;
 IF tg_op='UPDATE' AND old.unlinked_at IS NOT NULL AND
    new.unlinked_at IS DISTINCT FROM old.unlinked_at THEN
   RAISE EXCEPTION 'Removed links cannot be restored' USING ERRCODE='42501';
 END IF;
 IF new.created_by IS DISTINCT FROM auth.uid() AND tg_op='INSERT' THEN
   RAISE EXCEPTION 'Link creator must be signed-in member' USING ERRCODE='42501';
 END IF;
 IF NOT private.qa_item_link_exact_scope(new.from_kind,new.from_id,
  new.to_kind,new.to_id,new.space_id,new.private_space_id) THEN
  RAISE EXCEPTION 'Both linked records must belong to the same personal or shared space'
    USING ERRCODE='42501';
 END IF;
 RETURN NEW;
END $f$;
REVOKE ALL ON FUNCTION private.qa_link_immutable_endpoints() FROM PUBLIC,anon,authenticated;
DROP TRIGGER IF EXISTS zzz_qa_link_owner_guard ON public.item_links;
CREATE TRIGGER zzz_qa_link_owner_guard BEFORE INSERT OR UPDATE ON public.item_links
 FOR EACH ROW EXECUTE FUNCTION private.qa_link_immutable_endpoints();
GRANT SELECT,INSERT,UPDATE ON public.item_links TO authenticated;
