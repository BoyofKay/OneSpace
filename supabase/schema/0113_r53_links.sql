-- OneSpace R53 - Links between items (spec section 6, backlog B-17, decision D10).
-- Non-destructive: one new table with RLS and two read helpers.
--
-- A link exists only to save re-typing, carry a lifecycle or show origin.
-- Links are created by "Create from this" and shown in one "Linked items"
-- strip per item, both ways. A linked item the viewer cannot see (the
-- partner's Only-me item) is never shown, not even as "hidden item".

create table if not exists public.item_links (
  id uuid primary key default gen_random_uuid(),
  space_id uuid not null references public.spaces(id) on delete cascade,
  from_kind text not null,
  from_id uuid not null,
  to_kind text not null,
  to_id uuid not null,
  created_by uuid not null default auth.uid() references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  unlinked_at timestamptz,
  constraint item_links_kinds check (
    from_kind in ('activity','trip','occasion','experience','event','reminder','task','note','memory')
    and to_kind in ('activity','trip','occasion','experience','event','reminder','task','note','memory')),
  constraint item_links_not_self check (not (from_kind = to_kind and from_id = to_id))
);
comment on table public.item_links is
 'R53: links made by "Create from this". Shown both ways in the Linked items strip; Unlink stamps unlinked_at.';
create unique index if not exists item_links_pair on public.item_links(from_kind,from_id,to_kind,to_id)
  where unlinked_at is null;
create index if not exists item_links_from on public.item_links(from_kind,from_id);
create index if not exists item_links_to on public.item_links(to_kind,to_id);

-- Visible to the caller under each table's own access rules (SECURITY INVOKER).
create or replace function private.can_see_item(p_kind text, p_id uuid)
returns boolean language sql stable security invoker set search_path to '' as $$
 select case p_kind
  when 'activity' then exists(select 1 from public.activities where id=p_id)
  when 'trip' then exists(select 1 from public.shared_trips where id=p_id)
  when 'occasion' then exists(select 1 from public.occasion_plans where id=p_id)
  when 'experience' then exists(select 1 from public.shared_experiences where id=p_id)
  when 'event' then exists(select 1 from public.space_events where id=p_id)
  when 'reminder' then exists(select 1 from public.reminders where id=p_id)
  when 'task' then exists(select 1 from public.tasks where id=p_id)
  when 'note' then exists(select 1 from public.notes where id=p_id)
  when 'memory' then exists(select 1 from public.memories where id=p_id)
  else false end
$$;
grant execute on function private.can_see_item(text,uuid) to authenticated;

alter table public.item_links enable row level security;
drop policy if exists "Read links between items I can see" on public.item_links;
create policy "Read links between items I can see" on public.item_links for select to authenticated
 using (private.is_space_member(space_id)
   and private.can_see_item(from_kind,from_id) and private.can_see_item(to_kind,to_id));
drop policy if exists "Link items I can see" on public.item_links;
create policy "Link items I can see" on public.item_links for insert to authenticated
 with check (created_by=(select auth.uid()) and private.is_space_member(space_id)
   and private.can_see_item(from_kind,from_id) and private.can_see_item(to_kind,to_id));
drop policy if exists "Unlink items I can see" on public.item_links;
create policy "Unlink items I can see" on public.item_links for update to authenticated
 using (private.is_space_member(space_id)
   and private.can_see_item(from_kind,from_id) and private.can_see_item(to_kind,to_id))
 with check (private.is_space_member(space_id));
grant select, insert, update on public.item_links to authenticated;
revoke delete on public.item_links from authenticated, anon;

-- One call for the strip: links both ways plus a reminder's built-in source,
-- each with the other item's title, only for items the caller can see.
create or replace function public.item_linked(p_kind text, p_id uuid)
returns jsonb language sql stable security invoker set search_path to '' as $$
 with raw as (
   select l.id as link_id, l.to_kind as kind, l.to_id as id from public.item_links l
    where l.from_kind=p_kind and l.from_id=p_id and l.unlinked_at is null
   union all
   select l.id, l.from_kind, l.from_id from public.item_links l
    where l.to_kind=p_kind and l.to_id=p_id and l.unlinked_at is null
   union all
   -- A reminder's own source (to-do/checklist, event, occasion), both ways.
   select null, case r.source_kind when 'calendar' then 'event' else r.source_kind end, r.source_id
    from public.reminders r where p_kind='reminder' and r.id=p_id and r.source_id is not null
   union all
   select null, 'reminder', r.id from public.reminders r
    where r.source_id=p_id and r.archived_at is null
      and ((p_kind='task' and r.source_kind='task') or (p_kind='event' and r.source_kind='calendar')
        or (p_kind='occasion' and r.source_kind='occasion'))
 ), titled as (
   select r.link_id, r.kind, r.id, case r.kind
     when 'activity' then (select title from public.activities where id=r.id)
     when 'trip' then (select title from public.shared_trips where id=r.id)
     when 'occasion' then (select title from public.occasion_plans where id=r.id)
     when 'experience' then (select title from public.shared_experiences where id=r.id)
     when 'event' then (select title from public.space_events where id=r.id)
     when 'reminder' then (select title from public.reminders where id=r.id)
     when 'task' then (select title from public.tasks where id=r.id)
     when 'note' then (select title from public.notes where id=r.id)
     when 'memory' then (select title from public.memories where id=r.id) end as title
   from raw r
 )
 select coalesce(jsonb_agg(distinct jsonb_build_object('link_id',link_id,'kind',kind,'id',id,'title',title)),'[]'::jsonb)
 from titled where title is not null
$$;
revoke all on function public.item_linked(text,uuid) from public, anon;
grant execute on function public.item_linked(text,uuid) to authenticated;

-- Spec 6.2 (applied as r53_trip_end_updates_last_met): when How we live = Apart,
-- completing a shared trip updates "last time we met".
create or replace function private.trip_end_updates_last_met()
returns trigger language plpgsql security definer set search_path to '' as $$
declare v_day date;
begin
 if new.visibility<>'shared' or new.status<>'completed' or old.status='completed' then return new; end if;
 v_day:=least(coalesce(new.end_on,current_date),current_date);
 update public.spaces s set last_met_on=v_day
  where s.id=new.space_id and s.relationship_mode in ('apart_same_tz','apart_different_tz')
    and (s.last_met_on is null or s.last_met_on<v_day);
 return new;
end $$;
revoke all on function private.trip_end_updates_last_met() from public;
drop trigger if exists r53_trip_end_last_met on public.shared_trips;
create trigger r53_trip_end_last_met after update of status on public.shared_trips
 for each row execute function private.trip_end_updates_last_met();
