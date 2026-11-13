-- R17 additive shared selection of regional holiday calendars.
-- Turning a source off removes only its overlay; never modifies personal occasions.
create table public.space_holiday_sources (
 id uuid primary key default gen_random_uuid(),
 space_id uuid not null references public.spaces(id) on delete cascade,
 country_code text not null check(country_code in ('US','EG','SA')),
 enabled boolean not null default true,
 configured_by uuid not null default auth.uid() references auth.users(id),
 updated_at timestamptz not null default now(),
 unique(space_id,country_code)
);
create index space_holiday_sources_by_space on public.space_holiday_sources(space_id);
alter table public.space_holiday_sources enable row level security;
create policy "Members see shared holiday calendars" on public.space_holiday_sources
 for select to authenticated using(private.is_space_member(space_id));
create policy "Members add holiday calendar selection" on public.space_holiday_sources
 for insert to authenticated with check(private.is_space_member(space_id)
   and configured_by=(select auth.uid()));
create policy "Members enable or disable holiday calendar" on public.space_holiday_sources
 for update to authenticated using(private.is_space_member(space_id))
 with check(private.is_space_member(space_id));
revoke all on public.space_holiday_sources from public,anon,authenticated;
grant select on public.space_holiday_sources to authenticated;
grant insert(space_id,country_code,enabled) on public.space_holiday_sources to authenticated;
grant update(enabled) on public.space_holiday_sources to authenticated;
create function private.touch_holiday_source() returns trigger
 language plpgsql set search_path='' as $$
 begin new.updated_at=now(); return new;end $$;
create trigger holiday_source_updated before update on public.space_holiday_sources
 for each row execute function private.touch_holiday_source();
revoke all on function private.touch_holiday_source() from public,anon,authenticated;
alter publication supabase_realtime add table public.space_holiday_sources;
