-- R68 (Ahmed's forms review, Occasions & gifts). Non-destructive.
-- 1. An occasion can come from a saved holiday or a special date in the
--    calendar (source_kind + source_ref), instead of being typed from scratch.
-- 2. Status is automatic, like trips: Planning → Preparing (the prep window
--    has started) → Ready (gifts are bought and nothing is still reserved) →
--    Celebrated/Past (the date has gone). Only Cancelled is set by hand.

alter table public.occasion_plans
  add column if not exists source_kind text check (source_kind in ('holiday','calendar')),
  add column if not exists source_ref text check (char_length(source_ref) <= 200);

-- The next date an occasion falls on (its own date, or next year's for the
-- old "every year" plans; 29 Feb becomes 28 Feb).
create or replace function private.occasion_next_on(p_on date, p_annual boolean)
returns date language plpgsql stable set search_path to '' as $$
declare y int; d date;
begin
  if p_on is null then return null; end if;
  if not coalesce(p_annual,false) then return p_on; end if;
  for y in extract(year from current_date)::int .. extract(year from current_date)::int + 1 loop
    d := make_date(y, extract(month from p_on)::int,
      least(extract(day from p_on)::int,
        extract(day from (make_date(y, extract(month from p_on)::int, 1) + interval '1 month - 1 day'))::int));
    if d >= current_date then return d; end if;
  end loop;
  return d;
end $$;

create or replace function private.occasion_auto_status(
  p_plan uuid, p_on date, p_annual boolean, p_prep int, p_current text)
returns text language plpgsql stable security definer set search_path to '' as $$
declare v_next date; v_bought int; v_reserved int;
begin
  if p_current='cancelled' then return 'cancelled'; end if;
  if not coalesce(p_annual,false) and p_on < current_date then return 'celebrated'; end if;
  v_next := private.occasion_next_on(p_on, p_annual);
  select count(*) filter (where status='purchased'), count(*) filter (where status='planned')
    into v_bought, v_reserved
    from public.occasion_budget_items where plan_id=p_plan and archived_at is null;
  if v_bought > 0 and v_reserved = 0 then return 'ready'; end if;
  if v_next is not null and current_date >= v_next - coalesce(p_prep,30) then return 'preparing'; end if;
  return 'planning';
end $$;

create or replace function private.occasion_set_auto_status()
returns trigger language plpgsql security definer set search_path to '' as $$
begin
  new.status:=private.occasion_auto_status(new.id,new.occasion_on,new.annual,new.prep_lead_days,new.status);
  return new;
end $$;
drop trigger if exists r68_occasion_auto_status on public.occasion_plans;
create trigger r68_occasion_auto_status before insert or update of status,occasion_on,annual,prep_lead_days
  on public.occasion_plans for each row execute function private.occasion_set_auto_status();

create or replace function private.occasion_refresh_status(p_plan uuid)
returns void language plpgsql security definer set search_path to '' as $$
declare v_next text;
begin
  select private.occasion_auto_status(o.id,o.occasion_on,o.annual,o.prep_lead_days,o.status) into v_next
    from public.occasion_plans o where o.id=p_plan;
  if v_next is null then return; end if;
  update public.occasion_plans set status=v_next where id=p_plan and status is distinct from v_next;
end $$;

create or replace function private.occasion_item_changed()
returns trigger language plpgsql security definer set search_path to '' as $$
begin
  perform private.occasion_refresh_status(coalesce(new.plan_id,old.plan_id));
  return null;
end $$;
drop trigger if exists r68_item_refresh_occasion on public.occasion_budget_items;
create trigger r68_item_refresh_occasion after insert or update of status,archived_at or delete
  on public.occasion_budget_items for each row execute function private.occasion_item_changed();

create or replace function private.occasion_refresh_all_statuses()
returns integer language plpgsql security definer set search_path to '' as $$
declare v_count integer;
begin
  with next as (
    select o.id, private.occasion_auto_status(o.id,o.occasion_on,o.annual,o.prep_lead_days,o.status) s
      from public.occasion_plans o
     where o.archived_at is null and o.status not in ('cancelled','celebrated'))
  update public.occasion_plans o set status=n.s from next n
   where o.id=n.id and o.status is distinct from n.s;
  get diagnostics v_count=row_count;
  return v_count;
end $$;
revoke all on function private.occasion_refresh_all_statuses() from public, anon, authenticated;

do $$ begin
  perform cron.unschedule('onespace-occasion-status');
exception when others then null; end $$;
select cron.schedule('onespace-occasion-status','9 * * * *','select private.occasion_refresh_all_statuses();');

select private.occasion_refresh_all_statuses();

-- The app writes the new columns (column-level grants, as for the others).
grant insert (source_kind,source_ref) on public.occasion_plans to authenticated;
grant update (source_kind,source_ref) on public.occasion_plans to authenticated;
