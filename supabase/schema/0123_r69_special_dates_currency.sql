-- R69 (Ahmed): Settings › Birthdays, anniversary & special dates becomes a
-- configuration (not a second way into Occasions), and each person can set
-- a preferred currency next to the language.

alter table public.profiles
  add column if not exists preferred_currency text check (preferred_currency ~ '^[A-Z]{3}$');
grant update (preferred_currency) on public.profiles to authenticated;

create table if not exists public.space_special_dates (
  id uuid primary key default gen_random_uuid(),
  space_id uuid not null references public.spaces(id) on delete cascade,
  kind text not null check (kind in ('birthday','anniversary','custom')),
  person_id uuid references auth.users(id) on delete cascade,
  title text not null default '' check (char_length(title) <= 120),
  month smallint not null check (month between 1 and 12),
  day smallint not null check (day between 1 and 31),
  year smallint check (year between 1900 and 2100),
  created_by uuid not null default auth.uid() references auth.users(id) on delete cascade,
  archived_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (kind <> 'birthday' or person_id is not null),
  check (kind <> 'custom' or char_length(btrim(title)) >= 1)
);
-- One birthday per person and one anniversary per space.
create unique index if not exists space_special_dates_birthday
  on public.space_special_dates(space_id, person_id) where kind='birthday' and archived_at is null;
create unique index if not exists space_special_dates_anniversary
  on public.space_special_dates(space_id) where kind='anniversary' and archived_at is null;
create index if not exists space_special_dates_space on public.space_special_dates(space_id);

alter table public.space_special_dates enable row level security;

drop policy if exists special_dates_select on public.space_special_dates;
create policy special_dates_select on public.space_special_dates for select to authenticated
  using (exists(select 1 from public.space_members m where m.space_id=space_special_dates.space_id and m.user_id=auth.uid()));
drop policy if exists special_dates_insert on public.space_special_dates;
create policy special_dates_insert on public.space_special_dates for insert to authenticated
  with check (created_by=auth.uid() and exists(select 1 from public.space_members m
    where m.space_id=space_special_dates.space_id and m.user_id=auth.uid()));
drop policy if exists special_dates_update on public.space_special_dates;
create policy special_dates_update on public.space_special_dates for update to authenticated
  using (exists(select 1 from public.space_members m where m.space_id=space_special_dates.space_id and m.user_id=auth.uid()))
  with check (exists(select 1 from public.space_members m where m.space_id=space_special_dates.space_id and m.user_id=auth.uid()));

grant select, insert, update on public.space_special_dates to authenticated;

-- The birthday's person must belong to the space; keep updated_at fresh.
create or replace function private.special_date_check()
returns trigger language plpgsql security definer set search_path to '' as $$
begin
  if new.person_id is not null and not exists(select 1 from public.space_members m
     where m.space_id=new.space_id and m.user_id=new.person_id) then
    raise exception 'The person must be a member of this space';
  end if;
  if make_date(2000, new.month, 1) + (new.day - 1) * interval '1 day' >= make_date(2000, new.month, 1) + interval '1 month' then
    raise exception 'That day does not exist in this month';
  end if;
  new.updated_at:=now();
  return new;
end $$;
drop trigger if exists r69_special_date_check on public.space_special_dates;
create trigger r69_special_date_check before insert or update on public.space_special_dates
  for each row execute function private.special_date_check();

alter publication supabase_realtime add table public.space_special_dates;

-- An occasion can now come from a special date in this configuration.
alter table public.occasion_plans drop constraint if exists occasion_plans_source_kind_check;
alter table public.occasion_plans add constraint occasion_plans_source_kind_check
  check (source_kind in ('holiday','calendar','special'));
