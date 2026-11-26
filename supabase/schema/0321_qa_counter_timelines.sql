-- 0321 (26 Nov 2026, owner decision D100): named counter timelines.
-- A counter can sit on any number of timelines; each timeline has a name.
-- Same scope rules as counters: a personal timeline (private_space_id = owner,
-- only that owner) or a couple timeline (space_id, both current members).
-- A timeline only holds counters of its own scope.
-- QA first; Production at the next go-live.
-- Existing one-to-one links (space_counters.linked_counter_id) are moved onto
-- timelines below. The column stays for now (no longer written by the app).

create table if not exists public.counter_timelines (
  id uuid primary key default gen_random_uuid(),
  space_id uuid references public.spaces(id) on delete cascade,
  private_space_id uuid references public.user_private_spaces(owner_id) on delete cascade,
  created_by uuid not null default auth.uid() references auth.users(id) on delete cascade,
  title text not null check (char_length(btrim(title)) between 1 and 80),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint counter_timelines_one_scope check ((space_id is not null) <> (private_space_id is not null)),
  constraint counter_timelines_private_owner check (private_space_id is null or private_space_id = created_by)
);
create index if not exists counter_timelines_space_idx on public.counter_timelines(space_id) where space_id is not null;
create index if not exists counter_timelines_private_idx on public.counter_timelines(private_space_id) where private_space_id is not null;

create table if not exists public.counter_timeline_members (
  timeline_id uuid not null references public.counter_timelines(id) on delete cascade,
  counter_id uuid not null references public.space_counters(id) on delete cascade,
  added_by uuid default auth.uid() references auth.users(id) on delete set null,
  added_at timestamptz not null default now(),
  primary key (timeline_id, counter_id)
);
create index if not exists counter_timeline_members_counter_idx on public.counter_timeline_members(counter_id);

alter table public.counter_timelines enable row level security;
alter table public.counter_timeline_members enable row level security;

create or replace function private.can_use_counter_timeline(p_timeline uuid)
returns boolean language sql stable security definer set search_path to '' as $f$
  select exists (
    select 1 from public.counter_timelines t
    where t.id = p_timeline
      and ((t.private_space_id is not null and t.private_space_id = (select auth.uid()))
        or (t.space_id is not null and private.is_space_member(t.space_id))));
$f$;
revoke all on function private.can_use_counter_timeline(uuid) from public, anon;
grant execute on function private.can_use_counter_timeline(uuid) to authenticated;

drop policy if exists counter_timelines_rw on public.counter_timelines;
create policy counter_timelines_rw on public.counter_timelines for all to authenticated
  using ((private_space_id is not null and private_space_id = (select auth.uid()))
      or (space_id is not null and private.is_space_member(space_id)))
  with check ((private_space_id is not null and private_space_id = (select auth.uid()) and created_by = (select auth.uid()))
      or (space_id is not null and private.is_space_member(space_id)));

drop policy if exists counter_timeline_members_rw on public.counter_timeline_members;
create policy counter_timeline_members_rw on public.counter_timeline_members for all to authenticated
  using (private.can_use_counter_timeline(timeline_id))
  with check (private.can_use_counter_timeline(timeline_id));

grant select, insert, update, delete on public.counter_timelines to authenticated;
grant select, insert, delete on public.counter_timeline_members to authenticated;

-- Scope is fixed after creation; updated_at is kept by the server.
create or replace function private.counter_timeline_touch()
returns trigger language plpgsql security definer set search_path to '' as $f$
begin
  new.space_id := old.space_id; new.private_space_id := old.private_space_id;
  new.created_by := old.created_by; new.updated_at := now();
  return new;
end $f$;
drop trigger if exists counter_timeline_touch on public.counter_timelines;
create trigger counter_timeline_touch before update on public.counter_timelines
  for each row execute function private.counter_timeline_touch();

-- A timeline holds only counters of its own scope.
create or replace function private.counter_timeline_member_scope()
returns trigger language plpgsql security definer set search_path to '' as $f$
begin
  if not exists (
    select 1 from public.counter_timelines t join public.space_counters c on c.id = new.counter_id
    where t.id = new.timeline_id
      and c.space_id is not distinct from t.space_id
      and c.private_space_id is not distinct from t.private_space_id) then
    raise exception 'Counter is in another space';
  end if;
  return new;
end $f$;
drop trigger if exists counter_timeline_member_scope on public.counter_timeline_members;
create trigger counter_timeline_member_scope before insert on public.counter_timeline_members
  for each row execute function private.counter_timeline_member_scope();

-- Move existing links: every group of linked counters becomes one timeline,
-- named after its earliest counter. Runs once; harmless if repeated.
do $move$
declare
  seed record; members uuid[]; tl uuid; first_title text;
begin
  for seed in
    select c.id, c.space_id, c.private_space_id, c.created_by from public.space_counters c
    where c.linked_counter_id is not null
      and not exists (select 1 from public.counter_timeline_members m where m.counter_id = c.id)
  loop
    if exists (select 1 from public.counter_timeline_members m where m.counter_id = seed.id) then continue; end if;
    with recursive edges as (
      select id a, linked_counter_id b from public.space_counters where linked_counter_id is not null
      union all
      select linked_counter_id, id from public.space_counters where linked_counter_id is not null
    ), comp(id) as (
      select seed.id
      union
      select e.b from comp join edges e on e.a = comp.id
    )
    select array_agg(id) into members from comp;
    select c.title into first_title from public.space_counters c where c.id = any(members) order by c.on_date limit 1;
    insert into public.counter_timelines(space_id, private_space_id, created_by, title)
      values (seed.space_id, seed.private_space_id, seed.created_by, left(coalesce(first_title, 'Our timeline'), 80))
      returning id into tl;
    insert into public.counter_timeline_members(timeline_id, counter_id, added_by)
      select tl, c.id, seed.created_by from public.space_counters c
      where c.id = any(members)
        and c.space_id is not distinct from seed.space_id
        and c.private_space_id is not distinct from seed.private_space_id
      on conflict do nothing;
  end loop;
end $move$;
