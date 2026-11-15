-- R67 (Ahmed's forms review, Trips). Non-destructive.
-- 1. Trip setup moves to the first step: how we travel, one way / round trip,
--    who is traveling, passengers (as Google Flights counts them), flexible dates.
-- 2. Trip status is automatic: Planning → Booked (a flight option is booked or a
--    flight/stay is in the itinerary) → Traveling (on the dates) → Completed
--    (after the return date). Only Cancelled is set by hand.
-- 3. Flight options: cabin bags, checked bags, seat (yes/no + number).

alter table public.shared_trips
  add column if not exists travel_mode text not null default 'flight'
    check (travel_mode in ('flight','road','train','other')),
  add column if not exists trip_type text not null default 'round'
    check (trip_type in ('round','one_way')),
  add column if not exists traveler_id uuid references auth.users(id) on delete set null,
  add column if not exists adults smallint not null default 2 check (adults between 0 and 9),
  add column if not exists children smallint not null default 0 check (children between 0 and 9),
  add column if not exists infants smallint not null default 0 check (infants between 0 and 9),
  add column if not exists flexible_dates boolean not null default false;

alter table public.trip_flight_options
  add column if not exists cabin_bags smallint check (cabin_bags between 0 and 9),
  add column if not exists checked_bags smallint check (checked_bags between 0 and 9),
  add column if not exists seat_included boolean,
  add column if not exists seat_number text check (char_length(seat_number) <= 40);

-- The traveler must belong to the trip's space.
create or replace function private.trip_check_traveler()
returns trigger language plpgsql security definer set search_path to '' as $$
begin
  if new.traveler_id is not null and not exists(
    select 1 from public.space_members m
    where m.space_id=new.space_id and m.user_id=new.traveler_id) then
    raise exception 'The traveler must be a member of this space';
  end if;
  return new;
end $$;
drop trigger if exists r67_trip_traveler on public.shared_trips;
create trigger r67_trip_traveler before insert or update of traveler_id on public.shared_trips
  for each row execute function private.trip_check_traveler();

-- The automatic status for a trip.
create or replace function private.trip_auto_status(
  p_trip uuid, p_start date, p_end date, p_current text)
returns text language sql stable security definer set search_path to '' as $$
  select case
    when p_current='cancelled' then 'cancelled'
    when coalesce(p_end,p_start) is not null and coalesce(p_end,p_start) < current_date then 'completed'
    when p_start is not null and p_start <= current_date then 'traveling'
    when exists(select 1 from public.trip_flight_options f
                where f.trip_id=p_trip and f.archived_at is null and f.status='booked')
      or exists(select 1 from public.trip_items i
                where i.trip_id=p_trip and i.archived_at is null and i.kind in ('flight','stay'))
      then 'booked'
    else 'planning' end
$$;

create or replace function private.trip_set_auto_status()
returns trigger language plpgsql security definer set search_path to '' as $$
begin
  new.status:=private.trip_auto_status(new.id,new.start_on,new.end_on,new.status);
  return new;
end $$;
drop trigger if exists r67_trip_auto_status on public.shared_trips;
create trigger r67_trip_auto_status before insert or update of status,start_on,end_on
  on public.shared_trips for each row execute function private.trip_set_auto_status();

-- A booked flight option or a flight/stay in the itinerary refreshes the trip.
create or replace function private.trip_refresh_status(p_trip uuid)
returns void language plpgsql security definer set search_path to '' as $$
declare v_next text;
begin
  select private.trip_auto_status(t.id,t.start_on,t.end_on,t.status) into v_next
    from public.shared_trips t where t.id=p_trip;
  if v_next is null then return; end if;
  update public.shared_trips set status=v_next
   where id=p_trip and status is distinct from v_next;
end $$;

create or replace function private.trip_child_changed()
returns trigger language plpgsql security definer set search_path to '' as $$
begin
  perform private.trip_refresh_status(coalesce(new.trip_id,old.trip_id));
  return null;
end $$;
drop trigger if exists r67_flight_refresh_trip on public.trip_flight_options;
create trigger r67_flight_refresh_trip after insert or update of status,archived_at or delete
  on public.trip_flight_options for each row execute function private.trip_child_changed();
drop trigger if exists r67_item_refresh_trip on public.trip_items;
create trigger r67_item_refresh_trip after insert or update of kind,archived_at or delete
  on public.trip_items for each row execute function private.trip_child_changed();

-- Dates move on by themselves: refresh every hour.
create or replace function private.trip_refresh_all_statuses()
returns integer language plpgsql security definer set search_path to '' as $$
declare v_count integer;
begin
  with next as (
    select t.id, private.trip_auto_status(t.id,t.start_on,t.end_on,t.status) as s
      from public.shared_trips t
     where t.archived_at is null and t.status not in ('cancelled','completed'))
  update public.shared_trips t set status=n.s from next n
   where t.id=n.id and t.status is distinct from n.s;
  get diagnostics v_count=row_count;
  return v_count;
end $$;
revoke all on function private.trip_refresh_all_statuses() from public, anon, authenticated;

do $$ begin
  perform cron.unschedule('onespace-trip-status');
exception when others then null; end $$;
select cron.schedule('onespace-trip-status','7 * * * *','select private.trip_refresh_all_statuses();');

-- Bring existing trips in line once.
select private.trip_refresh_all_statuses();

-- The app writes these columns (column-level grants, as for the others).
grant insert (travel_mode,trip_type,traveler_id,adults,children,infants,flexible_dates)
  on public.shared_trips to authenticated;
grant update (travel_mode,trip_type,traveler_id,adults,children,infants,flexible_dates)
  on public.shared_trips to authenticated;
grant insert (cabin_bags,checked_bags,seat_included,seat_number)
  on public.trip_flight_options to authenticated;
grant update (cabin_bags,checked_bags,seat_included,seat_number)
  on public.trip_flight_options to authenticated;
