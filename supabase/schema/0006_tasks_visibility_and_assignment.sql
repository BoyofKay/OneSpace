-- OneSpace task ownership, private visibility and partner assignment.
-- Existing tasks remain shared; visibility is immutable after creation to avoid
-- leaking stale rows through an already-open realtime subscription.
alter table public.tasks
  add column visibility text not null default 'shared'
    check (visibility in ('shared', 'private')),
  add column assigned_to uuid references auth.users(id),
  add constraint task_private_assignee check
    (visibility = 'shared' or assigned_to is null or assigned_to = created_by);

drop policy "Partners can read shared tasks" on public.tasks;
drop policy "Partner creates tasks in their own space" on public.tasks;
drop policy "Partners can update shared tasks" on public.tasks;

create policy "Read shared tasks or my private tasks"
on public.tasks for select to authenticated
using (
  private.is_space_member(space_id)
  and (visibility = 'shared' or created_by = (select auth.uid()))
);

create policy "Create tasks in my space with valid assignee"
on public.tasks for insert to authenticated
with check (
  created_by = (select auth.uid())
  and private.is_space_member(space_id)
  and (
    assigned_to is null
    or exists (
      select 1 from public.space_members m
      where m.space_id = tasks.space_id
        and m.user_id = tasks.assigned_to
    )
  )
);

create policy "Update visible tasks with valid assignee"
on public.tasks for update to authenticated
using (
  private.is_space_member(space_id)
  and (visibility = 'shared' or created_by = (select auth.uid()))
)
with check (
  private.is_space_member(space_id)
  and (visibility = 'shared' or created_by = (select auth.uid()))
  and (
    assigned_to is null
    or exists (
      select 1 from public.space_members m
      where m.space_id = tasks.space_id
        and m.user_id = tasks.assigned_to
    )
  )
);

grant insert (visibility, assigned_to) on public.tasks to authenticated;
grant update (assigned_to) on public.tasks to authenticated;

create index tasks_private_by_creator on public.tasks(created_by, space_id)
where visibility = 'private';
create index tasks_by_assignee on public.tasks(space_id, assigned_to)
where assigned_to is not null;
