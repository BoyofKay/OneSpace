-- Reconciled 2026-11-20: applied to QA (ugwrpeduzyzrujkizqfo) on 2026-11-20 from
-- qa/activities-memories-two-scope-cutover-20261120:supabase/schema/0251_qa_occasion_budget_scope_aware_validation.sql (original number 0251). Kept verbatim so the
-- repository replays to the live QA schema. QA only; never apply to Production.
-- QA only: replace legacy budget trigger that demanded a couple space.
-- The parent plan is authoritative. Cross-scope Activity/option associations are denied.
CREATE OR REPLACE FUNCTION private.occasion_validate_budget_link()
RETURNS trigger LANGUAGE plpgsql SET search_path='' AS $q$
DECLARE plan_rec record; act_rec record; linked_activity uuid;
BEGIN
 SELECT p.space_id,p.private_space_id,p.created_by,p.visibility
   INTO plan_rec FROM public.occasion_plans p WHERE p.id=new.plan_id;
 IF NOT FOUND THEN
   RAISE EXCEPTION 'Occasion not accessible' USING ERRCODE='42501';
 END IF;
 IF plan_rec.private_space_id IS NOT NULL THEN
   IF plan_rec.private_space_id IS DISTINCT FROM auth.uid()
      OR plan_rec.created_by IS DISTINCT FROM auth.uid()
      OR plan_rec.space_id IS NOT NULL OR plan_rec.visibility<>'private' THEN
     RAISE EXCEPTION 'Personal occasion belongs to a different account'
       USING ERRCODE='42501';
   END IF;
 ELSE
   IF plan_rec.visibility<>'shared' OR plan_rec.space_id IS NULL
      OR NOT private.is_space_member(plan_rec.space_id) OR
      (SELECT count(*) FROM public.space_members sm WHERE sm.space_id=plan_rec.space_id)<>2 THEN
     RAISE EXCEPTION 'Shared occasion is not a current couple'
       USING ERRCODE='42501';
   END IF;
 END IF;
 IF new.source_component_id IS NOT NULL AND new.source_activity_id IS NULL THEN
   RAISE EXCEPTION 'Source component requires a source Activity';
 END IF;
 IF new.source_activity_id IS NOT NULL THEN
   SELECT a.space_id,a.private_space_id,a.visibility,a.created_by
     INTO act_rec FROM public.activities a WHERE a.id=new.source_activity_id;
   IF NOT FOUND OR act_rec.space_id IS DISTINCT FROM plan_rec.space_id OR
      act_rec.private_space_id IS DISTINCT FROM plan_rec.private_space_id OR
      act_rec.visibility IS DISTINCT FROM plan_rec.visibility THEN
     RAISE EXCEPTION 'Linked Activity must have the same current personal or shared scope'
       USING ERRCODE='42501';
   END IF;
   IF plan_rec.private_space_id IS NOT NULL AND act_rec.created_by IS DISTINCT FROM auth.uid() THEN
     RAISE EXCEPTION 'Personal Activity link belongs to another account'
       USING ERRCODE='42501';
   END IF;
   IF new.source_component_id IS NOT NULL THEN
     SELECT c.activity_id INTO linked_activity FROM public.activity_components c
        WHERE c.id=new.source_component_id;
     IF linked_activity IS DISTINCT FROM new.source_activity_id THEN
       RAISE EXCEPTION 'Source option does not belong to the selected Activity'
         USING ERRCODE='42501';
     END IF;
   END IF;
 END IF;
 new.updated_at=now();
 RETURN new;
END $q$;
REVOKE ALL ON FUNCTION private.occasion_validate_budget_link() FROM public,anon,authenticated;
