-- QA: proposals may reference budget items ONLY from the same occasion.
-- Enforced even when rows are inserted by a trusted privileged workflow.
CREATE OR REPLACE FUNCTION private.qa_occasion_proposal_item_same_plan()
RETURNS trigger LANGUAGE plpgsql SET search_path='' AS $q$
DECLARE v_proposal_plan uuid; v_budget_plan uuid;
BEGIN
 IF tg_op='UPDATE' AND (new.proposal_id IS DISTINCT FROM old.proposal_id OR
   new.item_id IS DISTINCT FROM old.item_id) THEN
  RAISE EXCEPTION 'Cannot reparent a proposal budget item' USING ERRCODE='42501';
 END IF;
 SELECT p.plan_id INTO v_proposal_plan FROM public.occasion_proposals p
   WHERE p.id=new.proposal_id;
 SELECT b.plan_id INTO v_budget_plan FROM public.occasion_budget_items b
   WHERE b.id=new.item_id;
 IF v_proposal_plan IS NULL OR v_budget_plan IS NULL OR v_proposal_plan<>v_budget_plan THEN
  RAISE EXCEPTION 'Proposal items must belong to the same occasion'
    USING ERRCODE='42501';
 END IF;
 RETURN NEW;
END $q$;
REVOKE ALL ON FUNCTION private.qa_occasion_proposal_item_same_plan()
 FROM public,anon,authenticated;
DROP TRIGGER IF EXISTS qa_proposal_item_same_plan ON public.occasion_proposal_items;
CREATE TRIGGER qa_proposal_item_same_plan BEFORE INSERT OR UPDATE
 ON public.occasion_proposal_items FOR EACH ROW
 EXECUTE FUNCTION private.qa_occasion_proposal_item_same_plan();
