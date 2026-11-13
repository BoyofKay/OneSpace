-- R19: additive checklist items and recurring list templates. Old tasks remain.
alter table public.tasks add column if not exists recurrence text not null default 'none'
 check(recurrence in ('none','daily','weekly','monthly','yearly'));

create table public.task_checklist_items(
 id uuid primary key default gen_random_uuid(),
 task_id uuid not null references public.tasks(id) on delete cascade,
 created_by uuid not null default auth.uid() references auth.users(id),
 title text not null check(char_length(btrim(title)) between 1 and 240),
 position int not null default 0,
 archived_at timestamptz,
 created_at timestamptz not null default now()
);
create index task_checklist_items_by_task on public.task_checklist_items(task_id,position,created_at);
alter table public.task_checklist_items enable row level security;
create policy "Read visible list items" on public.task_checklist_items
 for select to authenticated using(exists(
  select 1 from public.tasks t where t.id=task_id));
create policy "Add items to editable list" on public.task_checklist_items
 for insert to authenticated with check(
  created_by=(select auth.uid()) and exists(
   select 1 from public.tasks t where t.id=task_id and
    (t.visibility='shared' or t.created_by=(select auth.uid()))));
create policy "Edit items in editable list" on public.task_checklist_items
 for update to authenticated using(exists(
  select 1 from public.tasks t where t.id=task_id and
   (t.visibility='shared' or t.created_by=(select auth.uid()))))
 with check(exists(select 1 from public.tasks t where t.id=task_id and
  (t.visibility='shared' or t.created_by=(select auth.uid()))));
revoke all on public.task_checklist_items from public,anon,authenticated;
grant select on public.task_checklist_items to authenticated;
grant insert(task_id,title,position) on public.task_checklist_items to authenticated;
grant update(title,position,archived_at) on public.task_checklist_items to authenticated;

-- Completion per recurrence cycle, preserving prior weeks/days as history.
create table public.task_checklist_checks(
 id uuid primary key default gen_random_uuid(),
 item_id uuid not null references public.task_checklist_items(id) on delete cascade,
 cycle_date date not null,
 user_id uuid not null default auth.uid() references auth.users(id),
 completed boolean not null default true,
 updated_at timestamptz not null default now(),
 unique(item_id,cycle_date)
);
create index task_checklist_checks_cycle on public.task_checklist_checks(item_id,cycle_date);
alter table public.task_checklist_checks enable row level security;
create policy "Read checks of visible task" on public.task_checklist_checks
 for select to authenticated using(exists(
  select 1 from public.task_checklist_items i where i.id=item_id));
create policy "Create checklist check on editable list" on public.task_checklist_checks
 for insert to authenticated with check(
  user_id=(select auth.uid()) and exists(
  select 1 from public.task_checklist_items i join public.tasks t on t.id=i.task_id
  where i.id=item_id and(t.visibility='shared' or t.created_by=(select auth.uid()))));
create policy "Update check on editable list" on public.task_checklist_checks
 for update to authenticated using(exists(
  select 1 from public.task_checklist_items i join public.tasks t on t.id=i.task_id
  where i.id=item_id and(t.visibility='shared' or t.created_by=(select auth.uid()))))
 with check(exists(
  select 1 from public.task_checklist_items i join public.tasks t on t.id=i.task_id
  where i.id=item_id and(t.visibility='shared' or t.created_by=(select auth.uid()))));
revoke all on public.task_checklist_checks from public,anon,authenticated;
grant select on public.task_checklist_checks to authenticated;
grant insert(item_id,cycle_date,completed) on public.task_checklist_checks to authenticated;
grant update(completed,updated_at) on public.task_checklist_checks to authenticated;
grant update(recurrence) on public.tasks to authenticated;
alter publication supabase_realtime add table public.task_checklist_items;
alter publication supabase_realtime add table public.task_checklist_checks;
