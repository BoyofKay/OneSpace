-- Shared task foundation: one authoritative record visible to both members.
create table public.tasks (
  id uuid primary key default gen_random_uuid(),
  space_id uuid not null references public.spaces(id) on delete cascade,
  created_by uuid not null references auth.users(id),
  title text not null check (char_length(btrim(title)) between 1 and 120),
  priority text not null default 'normal' check (priority in ('low','normal','high')),
  target_date date,
  deadline_at timestamptz,
  status text not null default 'open' check (status in ('open','completed','cancelled')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index tasks_by_space_status on public.tasks (space_id, status, created_at desc);

create or replace function private.touch_task_updated_at()
returns trigger language plpgsql set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;
create trigger task_updated_at before update on public.tasks
for each row execute function private.touch_task_updated_at();

alter table public.tasks enable row level security;

create policy "Partners can read shared tasks"
on public.tasks for select to authenticated
using (private.is_space_member(space_id));

create policy "Partner creates tasks in their own space"
on public.tasks for insert to authenticated
with check (
  created_by = (select auth.uid())
  and private.is_space_member(space_id)
);

create policy "Partners can update shared tasks"
on public.tasks for update to authenticated
using (private.is_space_member(space_id))
with check (private.is_space_member(space_id));

revoke all on public.tasks from anon, authenticated;
grant select on public.tasks to authenticated;
grant insert (space_id, created_by, title, priority, target_date, deadline_at, status)
  on public.tasks to authenticated;
grant update (title, priority, target_date, deadline_at, status)
  on public.tasks to authenticated;
-- Deliberately do not grant DELETE: cancelled tasks remain in history.

-- Start with postgres_changes for this limited-scope MVP. RLS is enforced.
alter publication supabase_realtime add table public.tasks;
