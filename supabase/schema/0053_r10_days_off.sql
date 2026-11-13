-- Deployed 20261113120417 onespace_r10_personal_days_off_and_sleep_overrides
-- R10: per-user workdays-off and optional sleep overrides, shared to partner.
create table public.personal_days_off(
 id uuid primary key default gen_random_uuid(),
 space_id uuid not null references public.spaces(id) on delete cascade,
 user_id uuid not null references auth.users(id),
 off_date date not null,
 label text not null default 'Day off' check(length(label)<=120),
 night_before_sleep_at time,
 off_day_wake_at time,
 created_at timestamptz not null default now(),
 unique(user_id,off_date)
);
create index personal_days_off_space_date on public.personal_days_off(space_id,off_date);
alter table public.personal_days_off enable row level security;
create policy "Partners see their shared days off"
 on public.personal_days_off for select to authenticated
 using(private.is_space_member(space_id));
create policy "User creates own day off"
 on public.personal_days_off for insert to authenticated
 with check(user_id=(select auth.uid()) and private.is_space_member(space_id));
create policy "User edits own day off"
 on public.personal_days_off for update to authenticated
 using(user_id=(select auth.uid()) and private.is_space_member(space_id))
 with check(user_id=(select auth.uid()) and private.is_space_member(space_id));
create policy "User removes own day off"
 on public.personal_days_off for delete to authenticated
 using(user_id=(select auth.uid()) and private.is_space_member(space_id));
revoke all on public.personal_days_off from public,anon,authenticated;
grant select on public.personal_days_off to authenticated;
grant insert(space_id,user_id,off_date,label,night_before_sleep_at,off_day_wake_at)
 on public.personal_days_off to authenticated;
grant update(label,night_before_sleep_at,off_day_wake_at)
 on public.personal_days_off to authenticated;
grant delete on public.personal_days_off to authenticated;
alter publication supabase_realtime add table public.personal_days_off;
