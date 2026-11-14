-- R21: Narrow column privileges + non-destructive legacy task consolidation.
-- The four R20 standalone tasks become children of a named checklist.
-- Legacy task rows stay for traceability and rollback; the client hides them.
grant insert(recurrence) on public.tasks to authenticated;
grant insert(memory_type,photo_layout) on public.memories to authenticated;

alter table public.tasks
  add column if not exists migrated_to_list uuid references public.tasks(id) on delete set null;
alter table public.task_checklist_items
  add column if not exists legacy_task_id uuid references public.tasks(id) on delete set null;
alter table public.task_checklist_items
  add column if not exists legacy_status text;
alter table public.task_checklist_items
  add column if not exists legacy_target_date date;
alter table public.task_checklist_items
  add column if not exists legacy_assigned_to uuid references auth.users(id) on delete set null;
create unique index if not exists task_checklist_items_one_legacy
  on public.task_checklist_items(legacy_task_id) where legacy_task_id is not null;
create index if not exists tasks_migrated_to_list_idx
  on public.tasks(migrated_to_list) where migrated_to_list is not null;

with legacy_groups as (
  select space_id,created_by,visibility
  from public.tasks t
  where t.created_at < timestamptz '2026-11-14 00:00:00+00'
    and t.migrated_to_list is null
    and not exists (select 1 from public.task_checklist_items i where i.task_id=t.id)
  group by space_id,created_by,visibility
), new_lists as (
  insert into public.tasks(space_id,created_by,title,priority,status,visibility)
  select g.space_id,g.created_by,'Old checklist','normal','open',g.visibility
  from legacy_groups g
  returning id,space_id,created_by,visibility
), new_items as (
  insert into public.task_checklist_items(
    task_id,created_by,title,position,legacy_task_id,
    legacy_status,legacy_target_date,legacy_assigned_to)
  select new_lists.id,t.created_by,t.title,
     row_number() over(partition by new_lists.id order by t.created_at,t.id)::int,
     t.id,t.status,t.target_date,t.assigned_to
  from new_lists
  join public.tasks t on t.space_id=new_lists.space_id
    and t.created_by=new_lists.created_by
    and t.visibility=new_lists.visibility
  where t.created_at < timestamptz '2026-11-14 00:00:00+00'
    and t.migrated_to_list is null
    and not exists (select 1 from public.task_checklist_items i where i.task_id=t.id)
  returning task_id,legacy_task_id
)
update public.tasks t set migrated_to_list=i.task_id
  from new_items i where t.id=i.legacy_task_id;
