-- R17: identify who an important date celebrates; retain all older plans.
alter table public.occasion_plans add column honoree_name text not null default ''
 check (char_length(honoree_name)<=120);
grant insert(honoree_name) on public.occasion_plans to authenticated;
grant update(honoree_name) on public.occasion_plans to authenticated;
