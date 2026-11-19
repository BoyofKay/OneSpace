begin;
do $qa$
declare sid uuid; a uuid; b uuid; plan_id uuid; private_id uuid; other_id uuid; item_id uuid; prop_id uuid; foreign_item uuid;
 p jsonb; err text; n int;
begin
 select s.id,s.created_by,m.user_id into sid,a,b from public.spaces s
 join public.space_members m on m.space_id=s.id and m.user_id<>s.created_by
 where (select count(*) from public.space_members sm where sm.space_id=s.id)=2 limit 1;
 if sid is null then raise exception 'QA original pair fixture required';end if;
 insert into public.occasion_plans(space_id,created_by,title,occasion_on,visibility)
 values(sid,a,'QA budget for our holiday',current_date+15,'shared') returning id into plan_id;
 insert into public.occasion_budget_items(plan_id,created_by,title,notes,currency,unit_price)
 values(plan_id,b,'QA present for us','Written details, photo /storage/v1/object/public/secret.jpg','USD',85.40)
 returning id into item_id;
 insert into public.occasion_budget_log(plan_id,item_id,event_kind,actor_id,before_item,after_item)
 values(plan_id,item_id,'revised',b,'{"title":"First draft","photo_1_id":"11111111-2222-4333-8444-555555555555"}',
 '{"title":"Final written draft","voice_path":"secret-file.m4a"}');
 insert into public.occasion_plan_revisions(plan_id,record_kind,record_id,changed_by,before_snapshot,after_snapshot)
 values(plan_id,'plan',plan_id,a,'{"notes":"Before written history"}','{"notes":"After written history","file_path":"secret.pdf"}');
 insert into public.occasion_proposals(plan_id,created_by,title)
 values(plan_id,b,'Our gift choices') returning id into prop_id;
 insert into public.occasion_proposal_items(proposal_id,item_id) values(prop_id,item_id);
 if has_function_privilege('anon','private.qa_occasion_budget_history_preview(uuid)','execute')
 then raise exception 'Anonymous budget preview executable';end if;
 perform set_config('role','authenticated',true);
 perform set_config('request.jwt.claim.sub',a::text,true);
 p:=private.qa_occasion_budget_history_preview(plan_id);
 if p#>>'{payload,kind}'<>'shared_reference_only'
 or p::text not like '%QA present for us%'
 or p::text not like '%After written history%'
 or p::text not like '%Final written draft%'
 or p::text like '%/storage/v1/object%'
 or p::text like '%voice_path%'
 or p::text like '%photo_1_id%'
 or p->>'can_restore'<>'false'
 or (p#>>'{payload,child_record_count}')::int < 4
 then raise exception 'Occasion history missing entries or leaked media: %',left(p::text,1800);end if;
 if p->>'payload_sha256'<>encode(extensions.digest(convert_to((p->'payload')::text,'UTF8'),'sha256'),'hex')
 then raise exception 'Occasion package digest mismatch';end if;
 perform set_config('request.jwt.claim.sub',b::text,true);
 p:=private.qa_occasion_budget_history_preview(plan_id);
 if p#>>'{payload,recipient_id}'<>b::text or p::text not like '%QA present for us%'
 then raise exception 'Partner lost shared written budget history';end if;

 perform set_config('role','postgres',true);
 perform set_config('request.jwt.claim.sub',a::text,true);
 insert into public.occasion_plans(space_id,created_by,title,occasion_on,visibility)
 values(sid,a,'QA private purchase plan',current_date+10,'private') returning id into private_id;
 insert into public.occasion_budget_items(plan_id,created_by,title)
 values(private_id,a,'QA secret personal purchase');
 perform set_config('role','authenticated',true);
 perform set_config('request.jwt.claim.sub',a::text,true);
 p:=private.qa_occasion_budget_history_preview(private_id);
 if p#>>'{payload,kind}'<>'private_owner_only' or p::text not like '%QA secret personal purchase%'
 then raise exception 'Owner private budget export missing';end if;
 perform set_config('request.jwt.claim.sub',b::text,true);
 begin
 perform private.qa_occasion_budget_history_preview(private_id);
 raise exception 'Partner accessed private occasion budget';
 exception when others then
 get stacked diagnostics err=message_text;
 if err<>'Occasion plan not found' then raise exception 'Unexpected privacy result %',err;end if;
 end;

 -- Cross-plan item relation must fail, even when both plans are shared.
 perform set_config('role','postgres',true);
 insert into public.occasion_plans(space_id,created_by,title,occasion_on,visibility)
 values(sid,a,'QA another plan',current_date+20,'shared') returning id into other_id;
 insert into public.occasion_budget_items(plan_id,created_by,title)
 values(other_id,a,'QA foreign purchase') returning id into foreign_item;
 insert into public.occasion_proposal_items(proposal_id,item_id) values(prop_id,foreign_item);
 perform set_config('role','authenticated',true);
 perform set_config('request.jwt.claim.sub',a::text,true);
 begin
 perform private.qa_occasion_budget_history_preview(plan_id);
 raise exception 'Cross-plan proposal link entered a privacy preview';
 exception when others then
 get stacked diagnostics err=message_text;
 if err<>'Occasion proposal item cross-plan association mismatch' then
 raise exception 'Unexpected cross-plan rejection %',err;end if;
 end;
end $qa$;
rollback;
select 'PASS: occasion items, budget log, audit history and proposal item link, both partners, private plan denial, cross-plan failure, media scrubbing and SHA-256; rolled back' result;
