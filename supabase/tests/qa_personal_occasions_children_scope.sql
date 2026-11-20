-- QA Occasions ownership regression with rollback.
BEGIN;
SELECT set_config('qa.owner',(SELECT user_id::text FROM public.space_members ORDER BY space_id,user_id LIMIT 1),true);
SELECT set_config('qa.space',(SELECT space_id::text FROM public.space_members WHERE user_id::text=current_setting('qa.owner') LIMIT 1),true);
SELECT set_config('qa.peer',(SELECT user_id::text FROM public.space_members WHERE space_id::text=current_setting('qa.space') AND user_id::text<>current_setting('qa.owner') LIMIT 1),true);
SELECT set_config('qa.outside',(SELECT user_id::text FROM public.space_members WHERE space_id::text<>current_setting('qa.space') LIMIT 1),true);
SELECT set_config('request.jwt.claim.sub',current_setting('qa.owner'),true);
SET LOCAL ROLE authenticated;
DO $qa$
DECLARE a uuid:=current_setting('qa.owner')::uuid; b uuid:=current_setting('qa.peer')::uuid;
 c uuid:=current_setting('qa.outside')::uuid; pair uuid:=current_setting('qa.space')::uuid;
 personal uuid; shared uuid; bi uuid; st uuid; prop uuid; n int;
BEGIN
 IF a IS NULL OR b IS NULL OR c IS NULL OR pair IS NULL THEN
   RAISE EXCEPTION 'QA owner, partner, outsider required';END IF;
 INSERT INTO public.occasion_plans(private_space_id,created_by,visibility,title,occasion_on)
 VALUES(a,a,'private','QA personal birthday rollback',DATE '2027-01-10') RETURNING id INTO personal;
 INSERT INTO public.occasion_plans(space_id,created_by,visibility,title,occasion_on)
 VALUES(pair,a,'shared','QA shared anniversary rollback',DATE '2027-01-10') RETURNING id INTO shared;
 INSERT INTO public.occasion_budget_items(plan_id,created_by,title)
 VALUES(personal,a,'QA private gift') RETURNING id INTO bi;
 INSERT INTO public.occasion_plan_steps(plan_id,created_by,title)
 VALUES(personal,a,'QA private step') RETURNING id INTO st;
 INSERT INTO public.occasion_proposals(plan_id,created_by,title)
 VALUES(personal,a,'QA private plan option') RETURNING id INTO prop;
 INSERT INTO public.occasion_budget_items(plan_id,created_by,title)
 VALUES(shared,a,'QA shared gift');
 SELECT count(*) INTO n FROM public.record_action_history WHERE record_id=personal AND private_space_id=a;
 IF n=0 THEN RAISE EXCEPTION 'Owner cannot read private occasion audit';END IF;
 UPDATE public.occasion_plan_steps SET title='Edited private step' WHERE id=st;
 SELECT count(*) INTO n FROM public.occasion_plan_revisions WHERE plan_id=personal;
 IF n=0 THEN RAISE EXCEPTION 'Owner cannot read private occasion revisions';END IF;
 PERFORM set_config('request.jwt.claim.sub',b::text,true);
 SELECT count(*) INTO n FROM public.occasion_plans WHERE id=personal;
 IF n<>0 THEN RAISE EXCEPTION 'Partner sees private occasion';END IF;
 SELECT count(*) INTO n FROM public.occasion_budget_items WHERE id=bi;
 IF n<>0 THEN RAISE EXCEPTION 'Partner sees private occasion budget';END IF;
 SELECT count(*) INTO n FROM public.occasion_plan_steps WHERE id=st;
 IF n<>0 THEN RAISE EXCEPTION 'Partner sees private occasion steps';END IF;
 SELECT count(*) INTO n FROM public.occasion_proposals WHERE id=prop;
 IF n<>0 THEN RAISE EXCEPTION 'Partner sees private occasion proposal';END IF;
 SELECT count(*) INTO n FROM public.occasion_plan_revisions WHERE plan_id=personal;
 IF n<>0 THEN RAISE EXCEPTION 'Partner sees private occasion revisions';END IF;
 SELECT count(*) INTO n FROM public.occasion_plans WHERE id=shared;
 IF n<>1 THEN RAISE EXCEPTION 'Partner cannot see active shared occasion';END IF;
 PERFORM set_config('request.jwt.claim.sub',c::text,true);
 SELECT count(*) INTO n FROM public.occasion_plans WHERE id IN (personal,shared);
 IF n<>0 THEN RAISE EXCEPTION 'Outsider sees personal or paired occasion';END IF;
 PERFORM set_config('request.jwt.claim.sub',a::text,true);
 BEGIN
  UPDATE public.occasion_plans SET visibility='shared' WHERE id=personal;
  RAISE EXCEPTION 'BUG: private occasion shared via raw UPDATE';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM='BUG: private occasion shared via raw UPDATE' THEN RAISE;END IF;END;
 BEGIN
  UPDATE public.occasion_budget_items SET plan_id=shared WHERE id=bi;
  RAISE EXCEPTION 'BUG: private gift reparented to shared occasion';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM='BUG: private gift reparented to shared occasion' THEN RAISE;END IF;END;
 BEGIN
  INSERT INTO public.occasion_plans(space_id,created_by,visibility,title,occasion_on)
    VALUES(pair,a,'private','QA stale occasion',DATE '2027-01-11');
  RAISE EXCEPTION 'BUG: stale couple-private occasion created';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM='BUG: stale couple-private occasion created' THEN RAISE;END IF;END;
END $qa$;
ROLLBACK;
SELECT 'PASS personal/shared occasion, child budget/steps/proposals and revisions audit isolation; rolled back' result;