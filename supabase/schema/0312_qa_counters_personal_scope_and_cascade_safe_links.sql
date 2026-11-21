-- QA only (ugwrpeduzyzrujkizqfo). Never apply to Production.
-- 1. r77 link guard is scope-aware (space_id AND private_space_id must match)
--    and only checks links that actually change. Before, deleting a couple
--    space failed ("Counter is in another space") because the ON DELETE
--    SET NULL cascade re-checked links to rows already being deleted, and a
--    private counter could never link a private place or memory.
-- 2. Counters get account-owned private scope like the other modules.

create or replace function private.r77_same_space()
returns trigger language plpgsql security definer set search_path='' as $f$
declare ok boolean;
begin
  if tg_table_name = 'place_visits' then
    if tg_op='INSERT' or new.place_id is distinct from old.place_id then
      select (p.space_id is not distinct from new.space_id
              and p.private_space_id is not distinct from new.private_space_id) into ok
        from public.places p where p.id=new.place_id;
      if not coalesce(ok,false) then raise exception 'Place is in another space'; end if;
    end if;
    if new.memory_id is not null and (tg_op='INSERT' or new.memory_id is distinct from old.memory_id)
       and not exists(select 1 from public.memories m where m.id=new.memory_id
         and m.space_id is not distinct from new.space_id
         and m.private_space_id is not distinct from new.private_space_id) then
      raise exception 'Memory is in another space'; end if;
    return new;
  end if;
  if tg_table_name = 'places' then
    if new.planned_trip_id is not null
       and (tg_op='INSERT' or new.planned_trip_id is distinct from old.planned_trip_id)
       and not exists(select 1 from public.shared_trips t where t.id=new.planned_trip_id
         and t.space_id is not distinct from new.space_id
         and t.private_space_id is not distinct from new.private_space_id) then
      raise exception 'Trip is in another space'; end if;
  elsif tg_table_name = 'space_counters' then
    if new.place_id is not null and (tg_op='INSERT' or new.place_id is distinct from old.place_id)
       and not exists(select 1 from public.places p where p.id=new.place_id
         and p.space_id is not distinct from new.space_id
         and p.private_space_id is not distinct from new.private_space_id) then
      raise exception 'Place is in another space'; end if;
    if new.memory_id is not null and (tg_op='INSERT' or new.memory_id is distinct from old.memory_id)
       and not exists(select 1 from public.memories m where m.id=new.memory_id
         and m.space_id is not distinct from new.space_id
         and m.private_space_id is not distinct from new.private_space_id) then
      raise exception 'Memory is in another space'; end if;
    if new.linked_counter_id is not null
       and (tg_op='INSERT' or new.linked_counter_id is distinct from old.linked_counter_id)
       and not exists(select 1 from public.space_counters c where c.id=new.linked_counter_id
         and c.space_id is not distinct from new.space_id
         and c.private_space_id is not distinct from new.private_space_id) then
      raise exception 'Counter is in another space'; end if;
  end if;
  if tg_op = 'UPDATE' then
    new.space_id := old.space_id; new.private_space_id := old.private_space_id;
    new.created_by := old.created_by; new.updated_at := now();
  end if;
  return new;
end $f$;

-- Personal counters: owner only, never in a couple space.
drop policy if exists "QA owner reads personal counters" on public.space_counters;
create policy "QA owner reads personal counters" on public.space_counters
 for select to authenticated
 using(private_space_id=(select auth.uid()) and created_by=(select auth.uid())
   and visibility='private' and space_id is null);
drop policy if exists "QA owner inserts personal counters" on public.space_counters;
create policy "QA owner inserts personal counters" on public.space_counters
 for insert to authenticated
 with check(private_space_id=(select auth.uid()) and created_by=(select auth.uid())
   and visibility='private' and space_id is null);
drop policy if exists "QA owner updates personal counters" on public.space_counters;
create policy "QA owner updates personal counters" on public.space_counters
 for update to authenticated
 using(private_space_id=(select auth.uid()) and created_by=(select auth.uid()))
 with check(private_space_id=(select auth.uid()) and created_by=(select auth.uid())
   and visibility='private' and space_id is null);
-- Shared counters only between a current pair; private ones never in the couple.
drop policy if exists "QA active pair shared counters" on public.space_counters;
create policy "QA active pair shared counters" on public.space_counters
 as restrictive for insert to authenticated
 with check(private_space_id is not null or (visibility='shared' and space_id is not null
   and private.is_space_member(space_id)
   and (select count(*) from public.space_members m where m.space_id=space_counters.space_id)=2));
drop policy if exists "QA active pair updates shared counters" on public.space_counters;
create policy "QA active pair updates shared counters" on public.space_counters
 as restrictive for update to authenticated using(true)
 with check(private_space_id is not null or (visibility='shared' and space_id is not null
   and private.is_space_member(space_id)));

-- 3. Trips: a personal trip's traveler is its owner (or nobody); a couple
--    trip's traveler must be a member. The old check only knew space_id, so
--    every personal trip with a traveler failed.
create or replace function private.trip_check_traveler()
returns trigger language plpgsql security definer set search_path='' as $f$
begin
  if new.traveler_id is null then return new; end if;
  if new.private_space_id is not null then
    if new.traveler_id is distinct from new.private_space_id then
      raise exception 'A private trip can only be planned for yourself';
    end if;
  elsif not private.user_in_space(new.space_id,new.traveler_id) then
    raise exception 'The traveler must be a member of this space';
  end if;
  return new;
end $f$;

-- 4. Feelings: one private and one shared entry per person per day.
alter table public.daily_checkins drop constraint if exists daily_checkins_created_by_checkin_date_key;
drop index if exists public.daily_checkins_created_by_checkin_date_key;
create unique index if not exists qa_daily_checkins_shared_day_unique
  on public.daily_checkins(created_by,checkin_date) where space_id is not null;
