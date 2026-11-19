-- QA 0188: four occasion-budget descendants with strict cross-plan links.
-- Historical package only; no old order, purchase, shipping state replay.
do $guard$
begin
 if (select count(*) from private.qa_archive_table_policy where
 source_table in ('occasion_budget_items','occasion_budget_log',
 'occasion_plan_revisions','occasion_proposal_items')
 and disposition='review_required' and relation_kind='dependent' and not approved)<>4
 then raise exception 'Occasion budget/proposal archive scope must be reviewed';end if;
end $guard$;
update private.qa_archive_table_policy set approved=true,
 disposition='private_shared',reviewed_at=now(),
 policy_note=case source_table
 when 'occasion_budget_items' then 'Owner/private or original pair shared budget items; verify optional activity/component links belong to same space, remove old navigation identifiers, sanitize media and preserve written budget/order text; never replay purchases.'
 when 'occasion_budget_log' then 'Budget revisions tied to same parent plan and budget item, actor identity verified; scrub recursive before/after media; reference-only history.'
 when 'occasion_plan_revisions' then 'Audit event must refer to plan or a step on same plan; actor owner for private, original pair for shared, null system only for shared. Sanitize before/after snapshots.'
 else 'Proposal to budget item joins must reference items on exactly same occasion plan; proposal creator owner when private, original pair when shared. No cross-plan private link can travel.'
 end
where source_table in ('occasion_budget_items','occasion_budget_log',
'occasion_plan_revisions','occasion_proposal_items')
 and disposition='review_required' and not approved;

create or replace function private.qa_occasion_budget_history_preview(p_plan_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $fn$
declare me uuid:=auth.uid(); root public.occasion_plans%rowtype;
 bad int; total_count int; i jsonb; l jsonb; r jsonb; associations jsonb;
 package jsonb;
begin
 if me is null then raise exception 'Sign in required';end if;
 if (select count(*) from public.space_members where user_id=me)<>1
 then raise exception 'Occasion plan not found';end if;
 select p.* into root from public.occasion_plans p
 join public.space_members sm on sm.space_id=p.space_id and sm.user_id=me
 where p.id=p_plan_id and (p.visibility='shared' or p.created_by=me);
 if not found then raise exception 'Occasion plan not found';end if;
 if root.visibility not in ('shared','private')
 then raise exception 'Unsupported occasion visibility';end if;
 if not exists(select 1 from public.space_members sm
 where sm.space_id=root.space_id and sm.user_id=root.created_by)
 then raise exception 'Occasion owner lineage mismatch';end if;
 if (select count(*) from private.qa_archive_table_policy where approved and
 disposition='private_shared' and source_table in
 ('occasion_plans','occasion_budget_items','occasion_budget_log',
 'occasion_plan_revisions','occasion_proposal_items','occasion_proposals'))<>6
 then raise exception 'Occasion budget coverage not approved';end if;

 select count(*) into bad from public.occasion_budget_items x
 where x.plan_id=root.id and (
 (root.visibility='private' and x.created_by<>root.created_by)
 or (root.visibility='shared' and not exists(select 1 from public.space_members sm
   where sm.space_id=root.space_id and sm.user_id=x.created_by))
 or (x.source_activity_id is not null and not exists(select 1 from public.activities a
   where a.id=x.source_activity_id and a.space_id=root.space_id
     and (a.visibility='shared' or a.created_by=me)))
 or (x.source_component_id is not null and not exists(
    select 1 from public.activity_components ac
      join public.activities a on a.id=ac.activity_id
    where ac.id=x.source_component_id and a.space_id=root.space_id
      and (a.visibility='shared' or a.created_by=me)
      and (x.source_activity_id is null or a.id=x.source_activity_id)))
 );
 if bad>0 then raise exception 'Occasion item contributor or cross-space link mismatch';end if;

 select count(*) into bad from public.occasion_budget_log x
 where x.plan_id=root.id and (
 (root.visibility='private' and x.actor_id is distinct from root.created_by)
 or (root.visibility='shared' and x.actor_id is not null
   and not exists(select 1 from public.space_members sm
   where sm.space_id=root.space_id and sm.user_id=x.actor_id))
 or (x.item_id is not null and not exists(select 1 from public.occasion_budget_items it
   where it.id=x.item_id and it.plan_id=root.id))
 );
 if bad>0 then raise exception 'Occasion log actor or item lineage mismatch';end if;

 select count(*) into bad from public.occasion_plan_revisions x
 where x.plan_id=root.id and (
 (root.visibility='private' and x.changed_by is distinct from root.created_by)
 or (root.visibility='shared' and x.changed_by is not null
   and not exists(select 1 from public.space_members sm
   where sm.space_id=root.space_id and sm.user_id=x.changed_by))
 or (x.record_kind='plan' and x.record_id<>root.id)
 or (x.record_kind='step' and not exists(select 1 from public.occasion_plan_steps st
   where st.id=x.record_id and st.plan_id=root.id))
 );
 if bad>0 then raise exception 'Occasion revision actor or step lineage mismatch';end if;

 select count(*) into bad from public.occasion_proposals p
 where p.plan_id=root.id and (
 (root.visibility='private' and p.created_by<>root.created_by)
 or (root.visibility='shared' and not exists(select 1 from public.space_members sm
   where sm.space_id=root.space_id and sm.user_id=p.created_by)));
 if bad>0 then raise exception 'Occasion proposal contributor lineage mismatch';end if;
 select count(*) into bad
 from public.occasion_proposal_items link
 join public.occasion_proposals prop on prop.id=link.proposal_id
 where prop.plan_id=root.id and not exists(select 1 from public.occasion_budget_items item
 where item.id=link.item_id and item.plan_id=root.id);
 if bad>0 then raise exception 'Occasion proposal item cross-plan association mismatch';end if;
 -- Inverse links are also denied: a proposal from some other plan may point
 -- into our budget even if the regular forward scan doesn't find it.
 select count(*) into bad from public.occasion_proposal_items link
 join public.occasion_budget_items item on item.id=link.item_id
 join public.occasion_proposals prop on prop.id=link.proposal_id
 where item.plan_id=root.id and prop.plan_id<>root.id;
 if bad>0 then raise exception 'Occasion budget item attached to foreign proposal';end if;

 select (select count(*) from public.occasion_budget_items where plan_id=root.id)
   +(select count(*) from public.occasion_budget_log where plan_id=root.id)
   +(select count(*) from public.occasion_plan_revisions where plan_id=root.id)
   +(select count(*) from public.occasion_proposal_items link
       join public.occasion_proposals p on p.id=link.proposal_id where p.plan_id=root.id)
 into total_count;
 if total_count>500 then raise exception 'Occasion budget history exceeds 500 records';end if;
 select coalesce(jsonb_agg(jsonb_build_object('source_id',x.id,
 'structured',private.qa_structured_value(to_jsonb(x))
 -'source_activity_id'-'source_component_id') order by x.created_at,x.id),'[]'::jsonb)
 into i from public.occasion_budget_items x where x.plan_id=root.id;
 select coalesce(jsonb_agg(jsonb_build_object('source_id',x.id,
 'structured',private.qa_structured_value(to_jsonb(x))) order by x.logged_at,x.id),'[]'::jsonb)
 into l from public.occasion_budget_log x where x.plan_id=root.id;
 select coalesce(jsonb_agg(jsonb_build_object('source_id',x.id,
 'structured',private.qa_structured_value(to_jsonb(x))) order by x.changed_at,x.id),'[]'::jsonb)
 into r from public.occasion_plan_revisions x where x.plan_id=root.id;
 select coalesce(jsonb_agg(jsonb_build_object('proposal_id',x.proposal_id,
 'item_id',x.item_id,'created_at',x.created_at)
 order by x.proposal_id,x.item_id),'[]'::jsonb)
 into associations from public.occasion_proposal_items x
 join public.occasion_proposals p on p.id=x.proposal_id
 where p.plan_id=root.id;
 package:=jsonb_build_object('schema','onespace.occasion-budget-history-preview.v1',
 'kind',case when root.visibility='private' then 'private_owner_only' else 'shared_reference_only' end,
 'owner_id',root.created_by,'recipient_id',me,'source_space_id',root.space_id,
 'root',jsonb_build_object('table','occasion_plans','source_id',root.id,
 'structured',private.qa_structured_value(to_jsonb(root))-'source_ref'),
 'children',jsonb_build_object('occasion_budget_items',i,
   'occasion_budget_log',l,'occasion_plan_revisions',r,
   'occasion_proposal_items',associations),
 'child_record_count',total_count);
 if octet_length(convert_to(package::text,'UTF8'))>2097152
 then raise exception 'Occasion budget preview exceeds 2 MiB';end if;
 return jsonb_build_object('payload',package,
 'payload_sha256',encode(extensions.digest(convert_to(package::text,'UTF8'),'sha256'),'hex'),
 'media_included',false,'documents_included',false,'encrypted',false,
 'is_verified_archive',false,'can_restore',false,'safe_to_separate',false,
 'warning','Financial/order details are written history only. No purchases, external links, or shared relationship associations are restored.');
end $fn$;
revoke all on function private.qa_occasion_budget_history_preview(uuid) from public,anon,authenticated;
grant execute on function private.qa_occasion_budget_history_preview(uuid) to authenticated;
