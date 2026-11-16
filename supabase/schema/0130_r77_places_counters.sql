-- R77 (Ahmed's friend's ideas): Places (visited together + bucket list) and
-- Counters (days since / until, smart units, linked points). Both live in
-- the Remember tab. Shared = both partners see and edit; private = only me.

create table if not exists public.places (
  id uuid primary key default gen_random_uuid(),
  space_id uuid not null references public.spaces(id) on delete cascade,
  created_by uuid not null default auth.uid() references auth.users(id) on delete cascade,
  name text not null check (char_length(btrim(name)) between 1 and 120),
  address text not null default '' check (char_length(address) <= 300),
  city text not null default '' check (char_length(city) <= 120),
  country text not null default '' check (char_length(country) <= 80),
  category text not null default 'other' check (category in
    ('restaurant','cafe','city','beach','nature','hotel','landmark','shopping','activity','home','other')),
  status text not null default 'visited' check (status in ('visited','wishlist')),
  notes text not null default '' check (char_length(notes) <= 4000),
  favorite boolean not null default false,
  rating smallint check (rating between 1 and 5),
  wish_by date,
  planned_trip_id uuid references public.shared_trips(id) on delete set null,
  visibility text not null default 'shared' check (visibility in ('shared','private')),
  archived_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists places_space on public.places(space_id, status) where archived_at is null;

create table if not exists public.place_visits (
  id uuid primary key default gen_random_uuid(),
  place_id uuid not null references public.places(id) on delete cascade,
  space_id uuid not null references public.spaces(id) on delete cascade,
  created_by uuid not null default auth.uid() references auth.users(id) on delete cascade,
  visited_on date not null,
  caption text not null default '' check (char_length(caption) <= 2000),
  memory_id uuid references public.memories(id) on delete set null,
  created_at timestamptz not null default now()
);
create index if not exists place_visits_place on public.place_visits(place_id, visited_on desc);

create table if not exists public.space_counters (
  id uuid primary key default gen_random_uuid(),
  space_id uuid not null references public.spaces(id) on delete cascade,
  created_by uuid not null default auth.uid() references auth.users(id) on delete cascade,
  title text not null check (char_length(btrim(title)) between 1 and 120),
  on_date date not null,
  at_time time,
  description text not null default '' check (char_length(description) <= 4000),
  emoji text not null default '' check (char_length(emoji) <= 8),
  category text not null default 'love' check (category in
    ('love','family','home','travel','work','study','health','life','other')),
  place_id uuid references public.places(id) on delete set null,
  place_text text not null default '' check (char_length(place_text) <= 200),
  people text[] not null default '{}' check (cardinality(people) <= 20),
  memory_id uuid references public.memories(id) on delete set null,
  linked_counter_id uuid references public.space_counters(id) on delete set null,
  yearly boolean not null default false,
  pinned boolean not null default false,
  visibility text not null default 'shared' check (visibility in ('shared','private')),
  archived_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (linked_counter_id is null or linked_counter_id <> id)
);
create index if not exists space_counters_space on public.space_counters(space_id, on_date) where archived_at is null;

-- Everything linked must be in the same space; keep updated_at fresh.
create or replace function private.r77_same_space()
returns trigger language plpgsql security definer set search_path to '' as $$
declare s uuid;
begin
  if tg_table_name = 'place_visits' then
    select space_id into s from public.places where id = new.place_id;
    if s is distinct from new.space_id then raise exception 'Place is in another space'; end if;
    if new.memory_id is not null and not exists(select 1 from public.memories where id=new.memory_id and space_id=new.space_id) then
      raise exception 'Memory is in another space'; end if;
    return new;
  end if;
  if tg_table_name = 'places' then
    if new.planned_trip_id is not null and not exists(select 1 from public.shared_trips where id=new.planned_trip_id and space_id=new.space_id) then
      raise exception 'Trip is in another space'; end if;
  elsif tg_table_name = 'space_counters' then
    if new.place_id is not null and not exists(select 1 from public.places where id=new.place_id and space_id=new.space_id) then
      raise exception 'Place is in another space'; end if;
    if new.memory_id is not null and not exists(select 1 from public.memories where id=new.memory_id and space_id=new.space_id) then
      raise exception 'Memory is in another space'; end if;
    if new.linked_counter_id is not null and not exists(select 1 from public.space_counters where id=new.linked_counter_id and space_id=new.space_id) then
      raise exception 'Counter is in another space'; end if;
  end if;
  if tg_op = 'UPDATE' then
    new.space_id := old.space_id; new.created_by := old.created_by; new.updated_at := now();
  end if;
  return new;
end $$;
drop trigger if exists r77_places_guard on public.places;
create trigger r77_places_guard before insert or update on public.places for each row execute function private.r77_same_space();
drop trigger if exists r77_visits_guard on public.place_visits;
create trigger r77_visits_guard before insert or update on public.place_visits for each row execute function private.r77_same_space();
drop trigger if exists r77_counters_guard on public.space_counters;
create trigger r77_counters_guard before insert or update on public.space_counters for each row execute function private.r77_same_space();

alter table public.places enable row level security;
alter table public.place_visits enable row level security;
alter table public.space_counters enable row level security;

create policy places_select on public.places for select to authenticated
  using (private.is_space_member(space_id) and (visibility='shared' or created_by=(select auth.uid())));
create policy places_insert on public.places for insert to authenticated
  with check (created_by=(select auth.uid()) and private.is_space_member(space_id));
create policy places_update on public.places for update to authenticated
  using (private.is_space_member(space_id) and (visibility='shared' or created_by=(select auth.uid())))
  with check (private.is_space_member(space_id) and (visibility='shared' or created_by=(select auth.uid())));

create policy place_visits_select on public.place_visits for select to authenticated
  using (exists(select 1 from public.places p where p.id=place_visits.place_id));
create policy place_visits_insert on public.place_visits for insert to authenticated
  with check (created_by=(select auth.uid()) and exists(select 1 from public.places p where p.id=place_visits.place_id));
create policy place_visits_update on public.place_visits for update to authenticated
  using (created_by=(select auth.uid())) with check (created_by=(select auth.uid()));
create policy place_visits_delete on public.place_visits for delete to authenticated
  using (created_by=(select auth.uid()));

create policy counters_select on public.space_counters for select to authenticated
  using (private.is_space_member(space_id) and (visibility='shared' or created_by=(select auth.uid())));
create policy counters_insert on public.space_counters for insert to authenticated
  with check (created_by=(select auth.uid()) and private.is_space_member(space_id));
create policy counters_update on public.space_counters for update to authenticated
  using (private.is_space_member(space_id) and (visibility='shared' or created_by=(select auth.uid())))
  with check (private.is_space_member(space_id) and (visibility='shared' or created_by=(select auth.uid())));

grant select, insert, update on public.places, public.space_counters to authenticated;
grant select, insert, update, delete on public.place_visits to authenticated;

-- Tell the partner about a new shared place or counter.
create or replace function private.r77_notify_new()
returns trigger language plpgsql security definer set search_path to '' as $$
declare v_actor uuid := auth.uid(); v_peer uuid; v_kind text; v_detail text;
begin
  if v_actor is null or new.visibility <> 'shared' then return new; end if;
  v_kind := case tg_table_name when 'places' then 'place' else 'counter' end;
  for v_peer in select m.user_id from public.space_members m where m.space_id=new.space_id and m.user_id<>v_actor loop
    v_detail := case when tg_table_name='places' then
        case when (select coalesce(p.locale,'en') from public.profiles p where p.id=v_peer)='ar'
          then case to_jsonb(new)->>'status' when 'wishlist' then 'قائمة الأحلام' else 'زرناه معًا' end
          else case to_jsonb(new)->>'status' when 'wishlist' then 'Bucket list' else 'Been there together' end end
      else to_char((to_jsonb(new)->>'on_date')::date,'DD Mon YYYY') end;
    perform private.post_notice(new.space_id,v_peer,v_actor,'created',v_kind,new.id,
      coalesce(to_jsonb(new)->>'name',to_jsonb(new)->>'title'),'added',v_detail,interval '0',
      null,null,null,null,null,null);
  end loop;
  return new;
end $$;
drop trigger if exists r77_places_notice on public.places;
create trigger r77_places_notice after insert on public.places for each row execute function private.r77_notify_new();
drop trigger if exists r77_counters_notice on public.space_counters;
create trigger r77_counters_notice after insert on public.space_counters for each row execute function private.r77_notify_new();

-- "Ahmed added a place / a counter" in the push text.
do $m$
declare d text; before text;
begin
  d := pg_get_functiondef('private.compose_notification_text'::regproc);
  before := d;
  d := replace(d,
    $x$     when 'occasion' then case when ar then 'مناسبة' else 'an occasion' end
     else case when ar then 'عنصرًا' else 'an item' end end;$x$,
    $x$     when 'occasion' then case when ar then 'مناسبة' else 'an occasion' end
     when 'place' then case when ar then 'مكانًا' else 'a place' end
     when 'counter' then case when ar then 'عدّادًا' else 'a counter' end
     else case when ar then 'عنصرًا' else 'an item' end end;$x$);
  if d = before then raise exception 'compose_notification_text was not patched'; end if;
  execute d;
end $m$;

-- 0130b: notifications may point at a place or a counter.
alter table public.space_notifications drop constraint space_notifications_object_kind_check;
alter table public.space_notifications add constraint space_notifications_object_kind_check
  check (object_kind = any (array['activity','letter','calendar','gesture','note','checkin','checkin_request',
    'experience','trip','occasion','task','reminder','scrapbook','memory','space','place','counter']));
-- Tested 16 Nov 2026 (rolled back): partner sees/edits shared only, cannot
-- hide the other's place; stranger sees 0 and cannot insert; push text
-- "Ahmed added a place / Test Café · Been there together".
