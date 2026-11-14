begin;
 select set_config('qa.space',space_id::text,true) from public.space_members
  group by space_id having count(*)=2 limit 1;
 select set_config('qa.a',user_id::text,true) from public.space_members
  where space_id=current_setting('qa.space')::uuid order by joined_at limit 1;
 select set_config('qa.b',user_id::text,true) from public.space_members
  where space_id=current_setting('qa.space')::uuid order by joined_at desc limit 1;
 set local role authenticated;
 select set_config('request.jwt.claim.sub',current_setting('qa.a'),true);
 insert into public.occasion_plans(space_id,title,occasion_on,visibility)
 values(current_setting('qa.space')::uuid,'QA R23 GIFT OPTIONS',date '2026-12-25','private');
 select set_config('qa.plan',(select id::text from public.occasion_plans where title='QA R23 GIFT OPTIONS'),true);
 insert into public.occasion_budget_items(plan_id,title,currency,unit_price,merchant,estimated_delivery,preference_score,product_rating)
 values
 (current_setting('qa.plan')::uuid,'QA-EARLY','USD',65,'Walmart',date '2026-12-20',4,4.5),
 (current_setting('qa.plan')::uuid,'QA-LATE','USD',120,'Amazon',date '2026-12-28',5,4.5);
 select public.save_occasion_proposal(
  current_setting('qa.plan')::uuid,'QA First shortlist',
  array(select id from public.occasion_budget_items where plan_id=current_setting('qa.plan')::uuid),
  'Check delivery timing');
 do $test$
 begin
  if (select count(*) from public.occasion_proposal_items pi join public.occasion_proposals p
      on p.id=pi.proposal_id where p.plan_id=current_setting('qa.plan')::uuid)<>2
  then raise exception 'proposal did not retain selected options'; end if;
 end $test$;
 select set_config('request.jwt.claim.sub',current_setting('qa.b'),true);
 do $test$
 declare denied boolean:=false;
 begin
  if exists(select 1 from public.occasion_proposals where plan_id=current_setting('qa.plan')::uuid)
  then raise exception 'private proposal exposed to partner'; end if;
  begin
   perform public.save_occasion_proposal(current_setting('qa.plan')::uuid,
     'QA outsider',array[(select id from public.occasion_budget_items
      where plan_id=current_setting('qa.plan')::uuid limit 1)]::uuid[]);
  exception when others then denied:=true;end;
  if not denied then raise exception 'unauthorized proposal accepted'; end if;
 end $test$;
 select 'PASS: R23 occasion option metadata, private proposals and selection integrity' result;
 rollback;