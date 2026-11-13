-- R18: real occasion wishlists, budget commitments and decision-linked purchases.
-- Additive only: never reset accounts or alter existing occasion planning steps.
create table public.occasion_budget_items(
 id uuid primary key default gen_random_uuid(),
 plan_id uuid not null references public.occasion_plans(id) on delete cascade,
 created_by uuid not null default auth.uid() references auth.users(id),
 title text not null check(char_length(btrim(title)) between 1 and 200),
 quantity integer not null default 1 check(quantity between 1 and 999),
 unit_price numeric(12,2) check(unit_price >= 0),
 actual_unit_price numeric(12,2) check(actual_unit_price >= 0),
 currency text not null default 'USD' check(currency ~ '^[A-Z]{3}$'),
 status text not null default 'wish' check(status in
  ('wish','shortlisted','planned','purchased','cancelled')),
 source_activity_id uuid references public.activities(id) on delete set null,
 source_component_id uuid references public.activity_components(id) on delete set null,
 source_url text not null default '' check(char_length(source_url)<=1800),
 notes text not null default '' check(char_length(notes)<=2500),
 archived_at timestamptz,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create index occasion_budget_items_by_plan on public.occasion_budget_items(plan_id,status,updated_at desc);
create unique index occasion_budget_unique_active_option
 on public.occasion_budget_items(plan_id,source_component_id)
 where source_component_id is not null and archived_at is null;
alter table public.occasion_budget_items enable row level security;
create policy "Read purchases belonging to visible occasion" on public.occasion_budget_items
 for select to authenticated using(exists(
  select 1 from public.occasion_plans p where p.id=plan_id));
create policy "Add purchase to visible occasion" on public.occasion_budget_items
 for insert to authenticated with check(
  created_by=(select auth.uid()) and exists(
   select 1 from public.occasion_plans p where p.id=plan_id));
create policy "Update purchase in visible occasion" on public.occasion_budget_items
 for update to authenticated using(exists(
  select 1 from public.occasion_plans p where p.id=plan_id))
 with check(exists(select 1 from public.occasion_plans p where p.id=plan_id));
revoke all on public.occasion_budget_items from public,anon,authenticated;
grant select on public.occasion_budget_items to authenticated;
grant insert(plan_id,title,quantity,unit_price,actual_unit_price,currency,status,
 source_activity_id,source_component_id,source_url,notes)
 on public.occasion_budget_items to authenticated;
grant update(title,quantity,unit_price,actual_unit_price,currency,status,
 source_url,notes,archived_at) on public.occasion_budget_items to authenticated;

-- Immutable human-readable planning activity log, not a mutable form.
create table public.occasion_budget_log(
 id bigint generated always as identity primary key,
 plan_id uuid not null references public.occasion_plans(id) on delete cascade,
 item_id uuid references public.occasion_budget_items(id) on delete set null,
 event_kind text not null check(event_kind in ('added','revised')),
 actor_id uuid references auth.users(id),
 before_item jsonb,
 after_item jsonb,
 logged_at timestamptz not null default now()
);
create index occasion_budget_log_by_plan on public.occasion_budget_log(plan_id,logged_at desc);
alter table public.occasion_budget_log enable row level security;
create policy "Read budget history for visible occasion" on public.occasion_budget_log
 for select to authenticated using(exists(
  select 1 from public.occasion_plans p where p.id=plan_id));
revoke all on public.occasion_budget_log from public,anon,authenticated;
grant select on public.occasion_budget_log to authenticated;

-- Prevent linking a shared occasion to a private Activity. The snapshot
-- fields are useful if the original option is later archived, while this
-- validation prevents accidentally publishing a private wish through a link.
create function private.occasion_validate_budget_link() returns trigger
 language plpgsql security invoker set search_path='' as $$
declare v_plan_space uuid;v_plan_visibility text;
 v_activity_space uuid;v_activity_visibility text;v_component_activity uuid;
begin
 select p.space_id,p.visibility into v_plan_space,v_plan_visibility
  from public.occasion_plans p where p.id=new.plan_id;
 if v_plan_space is null then raise exception 'Occasion not accessible';end if;
 if new.source_component_id is not null and new.source_activity_id is null then
  raise exception 'Source component requires a source Activity';end if;
 if new.source_activity_id is not null then
  select a.space_id,a.visibility into v_activity_space,v_activity_visibility
   from public.activities a where a.id=new.source_activity_id;
  if v_activity_space is null or v_activity_space<>v_plan_space then
   raise exception 'Activity must belong to the same accessible shared space';end if;
  if v_plan_visibility='shared' and v_activity_visibility<>'shared' then
   raise exception 'Private Activity cannot be linked to a shared occasion';end if;
  if new.source_component_id is not null then
   select c.activity_id into v_component_activity
    from public.activity_components c where c.id=new.source_component_id;
   if v_component_activity is distinct from new.source_activity_id then
    raise exception 'Option does not belong to the selected Activity';end if;
  end if;
 end if;
 new.updated_at=now();
 return new;
end; $$;
create trigger occasion_budget_validate before insert or update on public.occasion_budget_items
 for each row execute function private.occasion_validate_budget_link();
revoke all on function private.occasion_validate_budget_link() from public,anon,authenticated;

create function private.occasion_budget_record_log() returns trigger
 language plpgsql security definer set search_path='' as $$
begin
 if TG_OP='UPDATE' and to_jsonb(old) is not distinct from to_jsonb(new) then
  return new;
 end if;
 insert into public.occasion_budget_log(
  plan_id,item_id,event_kind,actor_id,before_item,after_item)
 values(new.plan_id,new.id,case when TG_OP='INSERT' then 'added' else 'revised' end,
  auth.uid(),case when TG_OP='INSERT' then null else to_jsonb(old) end,to_jsonb(new));
 return new;
end; $$;
create trigger occasion_budget_history after insert or update on public.occasion_budget_items
 for each row execute function private.occasion_budget_record_log();
revoke all on function private.occasion_budget_record_log() from public,anon,authenticated;
alter publication supabase_realtime add table public.occasion_budget_items;
