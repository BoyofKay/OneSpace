-- R23 advanced checklist schedules: a versioned rule can be shared
-- without conflating assignment, visibility and per-partner check history.
alter table public.tasks add column if not exists recurrence_rule jsonb
 not null default '{}'::jsonb;
alter table public.tasks add constraint task_recurrence_rule_object
 check(jsonb_typeof(recurrence_rule)='object'
 and length(recurrence_rule::text)<=2500);
grant insert(recurrence_rule) on public.tasks to authenticated;
grant update(recurrence_rule) on public.tasks to authenticated;
