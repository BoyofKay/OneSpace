-- QA proposal cross-plan guard executes even in privileged association workflows.
BEGIN;
SELECT set_config('qa.owner',(SELECT user_id::text FROM public.space_members ORDER BY space_id,user_id LIMIT 1),true);
SELECT set_config('qa.space',(SELECT space_id::text FROM public.space_members WHERE user_id::text=current_setting('qa.owner') LIMIT 1),true);
SELECT set_config('request.jwt.claim.sub',current_setting('qa.owner'),true);
SET LOCAL ROLE authenticated;
DO $test$
DECLARE me uuid:=current_setting('qa.owner')::uuid;
pair uuid:=current_setting('qa.space')::uuid;
plan_private uuid;plan_shared uuid;item_private uuid; item_shared uuid; prop_private uuid;
BEGIN
 INSERT INTO public.occasion_plans(private_space_id,created_by,visibility,title,occasion_on)
  VALUES(me,me,'private','QA association private',DATE '2027-05-01') RETURNING id INTO plan_private;
 INSERT INTO public.occasion_plans(space_id,created_by,visibility,title,occasion_on)
  VALUES(pair,me,'shared','QA association shared',DATE '2027-05-01') RETURNING id INTO plan_shared;
 INSERT INTO public.occasion_budget_items(plan_id,title,created_by)
  VALUES(plan_private,'QA account item',me) RETURNING id INTO item_private;
 INSERT INTO public.occasion_budget_items(plan_id,title,created_by)
  VALUES(plan_shared,'QA pair item',me) RETURNING id INTO item_shared;
 INSERT INTO public.occasion_proposals(plan_id,created_by,title)
  VALUES(plan_private,me,'QA proposal') RETURNING id INTO prop_private;
 -- Direct client INSERT is not allowed for this join table: exercise the same
 -- database trigger via a privileged write, as trusted RPCs would.
 PERFORM set_config('role','postgres',true);
 INSERT INTO public.occasion_proposal_items(proposal_id,item_id)
  VALUES(prop_private,item_private);
 BEGIN
  INSERT INTO public.occasion_proposal_items(proposal_id,item_id)
   VALUES(prop_private,item_shared);
  RAISE EXCEPTION 'BUG: cross-scope proposal association accepted';
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM='BUG: cross-scope proposal association accepted' THEN RAISE;END IF;
 END;
END $test$;
ROLLBACK;
SELECT 'PASS same-plan proposal association and cross-scope rejection; rolled back' result;