-- Reconciled 2026-11-20: applied to QA (ugwrpeduzyzrujkizqfo) on 2026-11-20 from
-- qa/activities-memories-two-scope-cutover-20261120:supabase/schema/0250_qa_account_owned_occasions_and_children.sql (original number 0250). Kept verbatim so the
-- repository replays to the live QA schema. QA only; never apply to Production.
-- QA ONLY: account-private occasions and current couple occasions with inherited child ownership.
-- Do not move legacy rows or perform lifecycle deletion in this migration.
ALTER TABLE public.occasion_plans ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "QA private occasion read" ON public.occasion_plans;
CREATE POLICY "QA private occasion read" ON public.occasion_plans FOR SELECT TO authenticated
 USING(private_space_id=(select auth.uid()) and created_by=(select auth.uid())
   and space_id is null and visibility='private');
DROP POLICY IF EXISTS "QA private occasion insert" ON public.occasion_plans;
CREATE POLICY "QA private occasion insert" ON public.occasion_plans FOR INSERT TO authenticated
 WITH CHECK(private_space_id=(select auth.uid()) and created_by=(select auth.uid())
   and space_id is null and visibility='private');
DROP POLICY IF EXISTS "QA private occasion update" ON public.occasion_plans;
CREATE POLICY "QA private occasion update" ON public.occasion_plans FOR UPDATE TO authenticated
 USING(private_space_id=(select auth.uid()) and created_by=(select auth.uid())
   and space_id is null and visibility='private')
 WITH CHECK(private_space_id=(select auth.uid()) and created_by=(select auth.uid())
   and space_id is null and visibility='private');
DROP POLICY IF EXISTS "QA valid occasion read scope" ON public.occasion_plans;
CREATE POLICY "QA valid occasion read scope" ON public.occasion_plans
 AS RESTRICTIVE FOR SELECT TO authenticated USING(
  (private_space_id=(select auth.uid()) and created_by=(select auth.uid())
    and visibility='private' and space_id is null)
  OR (private_space_id is null and space_id is not null and visibility='shared'
    and private.is_space_member(space_id)
    and (select count(*) from public.space_members m where m.space_id=occasion_plans.space_id)=2));
DROP POLICY IF EXISTS "QA valid occasion insert scope" ON public.occasion_plans;
CREATE POLICY "QA valid occasion insert scope" ON public.occasion_plans
 AS RESTRICTIVE FOR INSERT TO authenticated WITH CHECK(
  (private_space_id=(select auth.uid()) and created_by=(select auth.uid())
    and visibility='private' and space_id is null)
  OR (private_space_id is null and space_id is not null and visibility='shared'
    and created_by=(select auth.uid()) and private.is_space_member(space_id)
    and (select count(*) from public.space_members m where m.space_id=occasion_plans.space_id)=2));
DROP POLICY IF EXISTS "QA valid occasion update scope" ON public.occasion_plans;
CREATE POLICY "QA valid occasion update scope" ON public.occasion_plans
 AS RESTRICTIVE FOR UPDATE TO authenticated
 USING((private_space_id=(select auth.uid()) and created_by=(select auth.uid())
    and visibility='private' and space_id is null)
  OR (private_space_id is null and space_id is not null and visibility='shared'
    and private.is_space_member(space_id)
    and (select count(*) from public.space_members m where m.space_id=occasion_plans.space_id)=2))
 WITH CHECK((private_space_id=(select auth.uid()) and created_by=(select auth.uid())
    and visibility='private' and space_id is null)
  OR (private_space_id is null and space_id is not null and visibility='shared'
    and private.is_space_member(space_id)
    and (select count(*) from public.space_members m where m.space_id=occasion_plans.space_id)=2));

CREATE OR REPLACE FUNCTION private.qa_occasion_scope_guard()
RETURNS trigger LANGUAGE plpgsql SET search_path='' AS $q$
BEGIN
 IF current_user NOT IN ('authenticated','anon') THEN RETURN NEW; END IF;
 IF tg_op='UPDATE' AND (old.space_id IS DISTINCT FROM new.space_id OR
  old.private_space_id IS DISTINCT FROM new.private_space_id OR
  old.created_by IS DISTINCT FROM new.created_by OR
  old.visibility IS DISTINCT FROM new.visibility) THEN
   RAISE EXCEPTION 'Cannot change occasion owner or scope in place' USING ERRCODE='42501';
 END IF;
 IF new.visibility='private' AND (
   new.private_space_id IS DISTINCT FROM auth.uid() OR
   new.space_id IS NOT NULL OR new.created_by IS DISTINCT FROM auth.uid()) THEN
  RAISE EXCEPTION 'Update OneSpace to store private occasions in your account' USING ERRCODE='42501';
 END IF;
 IF new.private_space_id IS NOT NULL AND
   (new.created_by IS DISTINCT FROM auth.uid() OR new.visibility<>'private' OR
    new.space_id IS NOT NULL OR new.private_space_id IS DISTINCT FROM auth.uid()) THEN
  RAISE EXCEPTION 'Personal occasion scope mismatch' USING ERRCODE='42501';
 END IF;
 RETURN NEW;
END $q$;
REVOKE ALL ON FUNCTION private.qa_occasion_scope_guard() FROM public,anon,authenticated;
DROP TRIGGER IF EXISTS zzz_qa_occasion_scope_guard ON public.occasion_plans;
CREATE TRIGGER zzz_qa_occasion_scope_guard BEFORE INSERT OR UPDATE
 ON public.occasion_plans FOR EACH ROW EXECUTE FUNCTION private.qa_occasion_scope_guard();

ALTER TABLE public.occasion_plan_steps ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "QA occasion_plan_steps reads owner parent" ON public.occasion_plan_steps;
CREATE POLICY "QA occasion_plan_steps reads owner parent" ON public.occasion_plan_steps
 AS RESTRICTIVE FOR SELECT TO authenticated USING(
 EXISTS(SELECT 1 FROM public.occasion_plans p WHERE p.id=occasion_plan_steps.plan_id
  AND ((p.private_space_id=(select auth.uid()) AND p.created_by=(select auth.uid())
    AND p.visibility='private' AND p.space_id IS NULL)
   OR(p.private_space_id IS NULL AND p.visibility='shared'
    AND private.is_space_member(p.space_id)
    AND (select count(*) from public.space_members m where m.space_id=p.space_id)=2))));
DROP POLICY IF EXISTS "QA occasion_plan_steps inserts owner parent" ON public.occasion_plan_steps;
CREATE POLICY "QA occasion_plan_steps inserts owner parent" ON public.occasion_plan_steps
 AS RESTRICTIVE FOR INSERT TO authenticated WITH CHECK(
 created_by=(select auth.uid()) AND EXISTS(
 SELECT 1 FROM public.occasion_plans p WHERE p.id=occasion_plan_steps.plan_id
  AND ((p.private_space_id=(select auth.uid()) AND p.created_by=(select auth.uid())
    AND p.visibility='private' AND p.space_id IS NULL)
   OR(p.private_space_id IS NULL AND p.visibility='shared'
    AND private.is_space_member(p.space_id)
    AND (select count(*) from public.space_members m where m.space_id=p.space_id)=2))));
DROP POLICY IF EXISTS "QA occasion_plan_steps updates owner parent" ON public.occasion_plan_steps;
CREATE POLICY "QA occasion_plan_steps updates owner parent" ON public.occasion_plan_steps
 AS RESTRICTIVE FOR UPDATE TO authenticated USING(
 EXISTS(SELECT 1 FROM public.occasion_plans p WHERE p.id=occasion_plan_steps.plan_id
  AND ((p.private_space_id=(select auth.uid()) AND p.created_by=(select auth.uid())
    AND p.visibility='private' AND p.space_id IS NULL)
   OR(p.private_space_id IS NULL AND p.visibility='shared'
    AND private.is_space_member(p.space_id)
    AND (select count(*) from public.space_members m where m.space_id=p.space_id)=2))))
 WITH CHECK(EXISTS(SELECT 1 FROM public.occasion_plans p WHERE p.id=occasion_plan_steps.plan_id
  AND ((p.private_space_id=(select auth.uid()) AND p.created_by=(select auth.uid())
    AND p.visibility='private' AND p.space_id IS NULL)
   OR(p.private_space_id IS NULL AND p.visibility='shared'
    AND private.is_space_member(p.space_id)
    AND (select count(*) from public.space_members m where m.space_id=p.space_id)=2))));

ALTER TABLE public.occasion_budget_items ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "QA occasion_budget_items reads owner parent" ON public.occasion_budget_items;
CREATE POLICY "QA occasion_budget_items reads owner parent" ON public.occasion_budget_items
 AS RESTRICTIVE FOR SELECT TO authenticated USING(
 EXISTS(SELECT 1 FROM public.occasion_plans p WHERE p.id=occasion_budget_items.plan_id
  AND ((p.private_space_id=(select auth.uid()) AND p.created_by=(select auth.uid())
    AND p.visibility='private' AND p.space_id IS NULL)
   OR(p.private_space_id IS NULL AND p.visibility='shared'
    AND private.is_space_member(p.space_id)
    AND (select count(*) from public.space_members m where m.space_id=p.space_id)=2))));
DROP POLICY IF EXISTS "QA occasion_budget_items inserts owner parent" ON public.occasion_budget_items;
CREATE POLICY "QA occasion_budget_items inserts owner parent" ON public.occasion_budget_items
 AS RESTRICTIVE FOR INSERT TO authenticated WITH CHECK(
 created_by=(select auth.uid()) AND EXISTS(
 SELECT 1 FROM public.occasion_plans p WHERE p.id=occasion_budget_items.plan_id
  AND ((p.private_space_id=(select auth.uid()) AND p.created_by=(select auth.uid())
    AND p.visibility='private' AND p.space_id IS NULL)
   OR(p.private_space_id IS NULL AND p.visibility='shared'
    AND private.is_space_member(p.space_id)
    AND (select count(*) from public.space_members m where m.space_id=p.space_id)=2))));
DROP POLICY IF EXISTS "QA occasion_budget_items updates owner parent" ON public.occasion_budget_items;
CREATE POLICY "QA occasion_budget_items updates owner parent" ON public.occasion_budget_items
 AS RESTRICTIVE FOR UPDATE TO authenticated USING(
 EXISTS(SELECT 1 FROM public.occasion_plans p WHERE p.id=occasion_budget_items.plan_id
  AND ((p.private_space_id=(select auth.uid()) AND p.created_by=(select auth.uid())
    AND p.visibility='private' AND p.space_id IS NULL)
   OR(p.private_space_id IS NULL AND p.visibility='shared'
    AND private.is_space_member(p.space_id)
    AND (select count(*) from public.space_members m where m.space_id=p.space_id)=2))))
 WITH CHECK(EXISTS(SELECT 1 FROM public.occasion_plans p WHERE p.id=occasion_budget_items.plan_id
  AND ((p.private_space_id=(select auth.uid()) AND p.created_by=(select auth.uid())
    AND p.visibility='private' AND p.space_id IS NULL)
   OR(p.private_space_id IS NULL AND p.visibility='shared'
    AND private.is_space_member(p.space_id)
    AND (select count(*) from public.space_members m where m.space_id=p.space_id)=2))));

ALTER TABLE public.occasion_proposals ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "QA occasion_proposals reads owner parent" ON public.occasion_proposals;
CREATE POLICY "QA occasion_proposals reads owner parent" ON public.occasion_proposals
 AS RESTRICTIVE FOR SELECT TO authenticated USING(
 EXISTS(SELECT 1 FROM public.occasion_plans p WHERE p.id=occasion_proposals.plan_id
  AND ((p.private_space_id=(select auth.uid()) AND p.created_by=(select auth.uid())
    AND p.visibility='private' AND p.space_id IS NULL)
   OR(p.private_space_id IS NULL AND p.visibility='shared'
    AND private.is_space_member(p.space_id)
    AND (select count(*) from public.space_members m where m.space_id=p.space_id)=2))));
DROP POLICY IF EXISTS "QA occasion_proposals inserts owner parent" ON public.occasion_proposals;
CREATE POLICY "QA occasion_proposals inserts owner parent" ON public.occasion_proposals
 AS RESTRICTIVE FOR INSERT TO authenticated WITH CHECK(
 created_by=(select auth.uid()) AND EXISTS(
 SELECT 1 FROM public.occasion_plans p WHERE p.id=occasion_proposals.plan_id
  AND ((p.private_space_id=(select auth.uid()) AND p.created_by=(select auth.uid())
    AND p.visibility='private' AND p.space_id IS NULL)
   OR(p.private_space_id IS NULL AND p.visibility='shared'
    AND private.is_space_member(p.space_id)
    AND (select count(*) from public.space_members m where m.space_id=p.space_id)=2))));
DROP POLICY IF EXISTS "QA occasion_proposals updates owner parent" ON public.occasion_proposals;
CREATE POLICY "QA occasion_proposals updates owner parent" ON public.occasion_proposals
 AS RESTRICTIVE FOR UPDATE TO authenticated USING(
 EXISTS(SELECT 1 FROM public.occasion_plans p WHERE p.id=occasion_proposals.plan_id
  AND ((p.private_space_id=(select auth.uid()) AND p.created_by=(select auth.uid())
    AND p.visibility='private' AND p.space_id IS NULL)
   OR(p.private_space_id IS NULL AND p.visibility='shared'
    AND private.is_space_member(p.space_id)
    AND (select count(*) from public.space_members m where m.space_id=p.space_id)=2))))
 WITH CHECK(EXISTS(SELECT 1 FROM public.occasion_plans p WHERE p.id=occasion_proposals.plan_id
  AND ((p.private_space_id=(select auth.uid()) AND p.created_by=(select auth.uid())
    AND p.visibility='private' AND p.space_id IS NULL)
   OR(p.private_space_id IS NULL AND p.visibility='shared'
    AND private.is_space_member(p.space_id)
    AND (select count(*) from public.space_members m where m.space_id=p.space_id)=2))));

ALTER TABLE public.occasion_plan_revisions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "QA occasion_plan_revisions follows parent" ON public.occasion_plan_revisions;
CREATE POLICY "QA occasion_plan_revisions follows parent" ON public.occasion_plan_revisions
 AS RESTRICTIVE FOR SELECT TO authenticated USING(EXISTS(SELECT 1 FROM public.occasion_plans p WHERE p.id=occasion_plan_revisions.plan_id
 AND ((p.private_space_id=(select auth.uid()) AND p.created_by=(select auth.uid()) AND p.space_id IS NULL)
  OR(p.private_space_id IS NULL AND p.visibility='shared' AND private.is_space_member(p.space_id)
  AND (SELECT count(*) FROM public.space_members m WHERE m.space_id=p.space_id)=2))));

ALTER TABLE public.occasion_budget_log ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "QA occasion_budget_log follows parent" ON public.occasion_budget_log;
CREATE POLICY "QA occasion_budget_log follows parent" ON public.occasion_budget_log
 AS RESTRICTIVE FOR SELECT TO authenticated USING(EXISTS(SELECT 1 FROM public.occasion_plans p WHERE p.id=occasion_budget_log.plan_id
 AND ((p.private_space_id=(select auth.uid()) AND p.created_by=(select auth.uid()) AND p.space_id IS NULL)
  OR(p.private_space_id IS NULL AND p.visibility='shared' AND private.is_space_member(p.space_id)
  AND (SELECT count(*) FROM public.space_members m WHERE m.space_id=p.space_id)=2))));

ALTER TABLE public.occasion_proposal_items ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "QA occasion_proposal_items follows parent" ON public.occasion_proposal_items;
CREATE POLICY "QA occasion_proposal_items follows parent" ON public.occasion_proposal_items
 AS RESTRICTIVE FOR SELECT TO authenticated USING(EXISTS(SELECT 1 FROM public.occasion_proposals prop
 JOIN public.occasion_budget_items item ON item.id=occasion_proposal_items.item_id
 JOIN public.occasion_plans p ON p.id=prop.plan_id
 WHERE prop.id=occasion_proposal_items.proposal_id AND item.plan_id=prop.plan_id
 AND ((p.private_space_id=(select auth.uid()) AND p.created_by=(select auth.uid()) AND p.space_id IS NULL)
  OR(p.private_space_id IS NULL AND p.visibility='shared' AND private.is_space_member(p.space_id)
  AND (SELECT count(*) FROM public.space_members m WHERE m.space_id=p.space_id)=2))));

-- Cross-links must never point from a personal occasion to a former shared
-- Activity or from the current couple to a private Activity.
CREATE OR REPLACE FUNCTION private.qa_occasion_child_guard()
RETURNS trigger LANGUAGE plpgsql SET search_path='' AS $q$
DECLARE p record;
BEGIN
 IF current_user NOT IN ('authenticated','anon') THEN RETURN NEW; END IF;
 IF tg_op='UPDATE' AND (new.plan_id IS DISTINCT FROM old.plan_id OR
   new.created_by IS DISTINCT FROM old.created_by) THEN
  RAISE EXCEPTION 'Cannot change occasion child parent or author' USING ERRCODE='42501';
 END IF;
 IF tg_op='INSERT' AND new.created_by IS DISTINCT FROM auth.uid() THEN
  RAISE EXCEPTION 'Occasion child creator mismatch' USING ERRCODE='42501';
 END IF;
 IF tg_table_name='occasion_budget_items' THEN
   SELECT space_id,private_space_id INTO p FROM public.occasion_plans
   WHERE id=new.plan_id;
   IF new.source_activity_id IS NOT NULL AND NOT EXISTS(
    SELECT 1 FROM public.activities a WHERE a.id=new.source_activity_id
      AND a.space_id IS NOT DISTINCT FROM p.space_id
      AND a.private_space_id IS NOT DISTINCT FROM p.private_space_id) THEN
      RAISE EXCEPTION 'Cannot link another scope Activity to this occasion' USING ERRCODE='42501';
   END IF;
   IF new.source_component_id IS NOT NULL AND NOT EXISTS(
    SELECT 1 FROM public.activity_components c
     JOIN public.activities a ON a.id=c.activity_id
     WHERE c.id=new.source_component_id
       AND a.space_id IS NOT DISTINCT FROM p.space_id
       AND a.private_space_id IS NOT DISTINCT FROM p.private_space_id
       AND (new.source_activity_id IS NULL OR a.id=new.source_activity_id)) THEN
      RAISE EXCEPTION 'Linked option must belong to the same scoped Activity' USING ERRCODE='42501';
   END IF;
 END IF;
 RETURN NEW;
END $q$;
REVOKE ALL ON FUNCTION private.qa_occasion_child_guard() FROM public,anon,authenticated;
DROP TRIGGER IF EXISTS zzz_qa_occasion_child_guard ON public.occasion_plan_steps;
CREATE TRIGGER zzz_qa_occasion_child_guard BEFORE INSERT OR UPDATE ON public.occasion_plan_steps
 FOR EACH ROW EXECUTE FUNCTION private.qa_occasion_child_guard();
DROP TRIGGER IF EXISTS zzz_qa_occasion_child_guard ON public.occasion_budget_items;
CREATE TRIGGER zzz_qa_occasion_child_guard BEFORE INSERT OR UPDATE ON public.occasion_budget_items
 FOR EACH ROW EXECUTE FUNCTION private.qa_occasion_child_guard();
DROP TRIGGER IF EXISTS zzz_qa_occasion_child_guard ON public.occasion_proposals;
CREATE TRIGGER zzz_qa_occasion_child_guard BEFORE INSERT OR UPDATE ON public.occasion_proposals
 FOR EACH ROW EXECUTE FUNCTION private.qa_occasion_child_guard();

DROP POLICY IF EXISTS "QA owner reads personal occasion action history" ON public.record_action_history;
CREATE POLICY "QA owner reads personal occasion action history" ON public.record_action_history
 FOR SELECT TO authenticated USING(record_kind='occasion' AND private_space_id=(select auth.uid())
  AND EXISTS(SELECT 1 FROM public.occasion_plans p WHERE p.id=record_id
    AND p.private_space_id=(select auth.uid()) AND p.created_by=(select auth.uid())
    AND p.visibility='private' AND p.space_id IS NULL));
GRANT SELECT,INSERT,UPDATE ON public.occasion_plans,public.occasion_plan_steps,
 public.occasion_budget_items,public.occasion_proposals TO authenticated;
GRANT SELECT ON public.occasion_budget_log,public.occasion_plan_revisions,public.occasion_proposal_items TO authenticated;
