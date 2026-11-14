-- R23: actionable shopping comparisons, order status and reusable proposed combinations.
-- Adds optional metadata to already-protected occasion budget items.
alter table public.occasion_budget_items
 add column if not exists merchant text not null default '' check(length(merchant)<=140),
 add column if not exists estimated_delivery date,
 add column if not exists product_rating numeric(2,1)
   check(product_rating between 0 and 5),
 add column if not exists preference_score integer check(preference_score between 1 and 5),
 add column if not exists order_status text not null default 'not_ordered'
   check(order_status in ('not_ordered','ordered','shipped','delivered','return_requested','returned','cancelled')),
 add column if not exists order_number text not null default '' check(length(order_number)<=160),
 add column if not exists tracking_url text not null default '' check(length(tracking_url)<=1800),
 add column if not exists return_reason text not null default '' check(length(return_reason)<=600);
grant insert(merchant,estimated_delivery,product_rating,preference_score,
 order_status,order_number,tracking_url,return_reason)
 on public.occasion_budget_items to authenticated;
grant update(merchant,estimated_delivery,product_rating,preference_score,
 order_status,order_number,tracking_url,return_reason)
 on public.occasion_budget_items to authenticated;

create table public.occasion_proposals(
 id uuid primary key default gen_random_uuid(),
 plan_id uuid not null references public.occasion_plans(id) on delete cascade,
 created_by uuid not null default auth.uid() references auth.users(id),
 title text not null check(char_length(btrim(title)) between 1 and 120),
 notes text not null default '' check(length(notes)<=1000),
 status text not null default 'proposed'
  check(status in ('proposed','approved','superseded')),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create index occasion_proposals_plan_created on public.occasion_proposals(plan_id,created_at desc);
alter table public.occasion_proposals enable row level security;
create policy "Read proposals under visible occasions" on public.occasion_proposals
 for select to authenticated using (exists(
 select 1 from public.occasion_plans p where p.id=plan_id));
create policy "Add proposal to visible occasion" on public.occasion_proposals
 for insert to authenticated with check(created_by=(select auth.uid())
 and exists(select 1 from public.occasion_plans p where p.id=plan_id));
create policy "Edit proposal under visible occasion" on public.occasion_proposals
 for update to authenticated using(exists(
 select 1 from public.occasion_plans p where p.id=plan_id))
 with check(exists(select 1 from public.occasion_plans p where p.id=plan_id));
revoke all on public.occasion_proposals from public,anon,authenticated;
grant select on public.occasion_proposals to authenticated;
grant insert(plan_id,title,notes) on public.occasion_proposals to authenticated;
grant update(title,notes,status,updated_at) on public.occasion_proposals to authenticated;

create table public.occasion_proposal_items (
 proposal_id uuid not null references public.occasion_proposals(id) on delete cascade,
 item_id uuid not null references public.occasion_budget_items(id) on delete restrict,
 created_at timestamptz not null default now(),
 primary key(proposal_id,item_id)
);
create index occasion_proposal_items_by_item on public.occasion_proposal_items(item_id);
alter table public.occasion_proposal_items enable row level security;
create policy "Read proposal entries with visible parent" on public.occasion_proposal_items
 for select to authenticated using(exists(
 select 1 from public.occasion_proposals p where p.id=proposal_id));
-- Proposal contents are inserted through one verified RPC for an atomic snapshot.
revoke all on public.occasion_proposal_items from public,anon,authenticated;
grant select on public.occasion_proposal_items to authenticated;

create function public.save_occasion_proposal(
 p_plan_id uuid,p_title text,p_item_ids uuid[],p_notes text default '')
returns uuid language plpgsql security definer set search_path='' as $$
declare new_id uuid; count_ids integer;
begin
 if auth.uid() is null or p_plan_id is null or
   char_length(btrim(coalesce(p_title,''))) not between 1 and 120
   or char_length(coalesce(p_notes,''))>1000
   or p_item_ids is null or cardinality(p_item_ids) not between 1 and 100
 then raise exception 'Select one or more products and a proposal name'; end if;
 if not exists(select 1 from public.occasion_plans p
   where p.id=p_plan_id and
    exists(select 1 from public.space_members m
      where m.space_id=p.space_id and m.user_id=auth.uid())
   and (p.visibility='shared' or p.created_by=auth.uid())) then
   raise exception 'Occasion unavailable';
 end if;
 select count(distinct i.id) into count_ids
 from public.occasion_budget_items i
 where i.plan_id=p_plan_id and i.id=any(p_item_ids)
  and i.archived_at is null and i.status<>'cancelled';
 if count_ids<>cardinality(p_item_ids) then
  raise exception 'A selected product is unavailable or duplicated';
 end if;
 insert into public.occasion_proposals(plan_id,created_by,title,notes)
 values(p_plan_id,auth.uid(),btrim(p_title),coalesce(p_notes,''))
 returning id into new_id;
 insert into public.occasion_proposal_items(proposal_id,item_id)
 select new_id,unnest(p_item_ids);
 return new_id;
end $$;
revoke all on function public.save_occasion_proposal(uuid,text,uuid[],text)
 from public,anon,authenticated;
grant execute on function public.save_occasion_proposal(uuid,text,uuid[],text) to authenticated;
