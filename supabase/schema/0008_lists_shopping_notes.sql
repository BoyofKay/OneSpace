-- OneSpace: shared/private lists, shopping items and collaborative notes.
-- All private/shared scopes are fixed at creation. Removing a row archives
-- or soft-deletes it to keep client reconciliation and audit predictable.

create table public.lists (
  id uuid primary key default gen_random_uuid(),
  space_id uuid not null references public.spaces(id) on delete cascade,
  created_by uuid not null references auth.users(id),
  title text not null check (char_length(btrim(title)) between 1 and 120),
  kind text not null default 'checklist' check (kind in ('checklist', 'shopping')),
  visibility text not null default 'shared' check (visibility in ('shared', 'private')),
  archived_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index lists_space_recent on public.lists(space_id,created_at desc);
create index lists_private_owner on public.lists(space_id,created_by)
  where visibility = 'private';

create table public.list_items (
  id uuid primary key default gen_random_uuid(),
  list_id uuid not null references public.lists(id) on delete cascade,
  created_by uuid not null references auth.users(id),
  label text not null check (char_length(btrim(label)) between 1 and 200),
  quantity numeric(10,2) not null default 1 check (quantity > 0 and quantity <= 99999),
  unit text not null default '' check (char_length(unit) <= 24),
  note text not null default '' check (char_length(note) <= 500),
  checked boolean not null default false,
  removed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index list_items_by_list on public.list_items(list_id,created_at);

create table public.notes (
  id uuid primary key default gen_random_uuid(),
  space_id uuid not null references public.spaces(id) on delete cascade,
  created_by uuid not null references auth.users(id),
  title text not null check (char_length(btrim(title)) between 1 and 120),
  body text not null default '' check (char_length(body) <= 30000),
  visibility text not null default 'shared' check (visibility in ('shared','private')),
  pinned boolean not null default false,
  archived_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index notes_space_recent on public.notes(space_id,updated_at desc);
create index notes_private_owner on public.notes(space_id,created_by)
  where visibility='private';

create trigger lists_updated_at before update on public.lists
for each row execute function private.touch_task_updated_at();
create trigger list_items_updated_at before update on public.list_items
for each row execute function private.touch_task_updated_at();
create trigger notes_updated_at before update on public.notes
for each row execute function private.touch_task_updated_at();

alter table public.lists enable row level security;
alter table public.list_items enable row level security;
alter table public.notes enable row level security;

create policy "Visible lists" on public.lists for select to authenticated
using (private.is_space_member(space_id) and
  (visibility='shared' or created_by=(select auth.uid())));
create policy "Create list in my space" on public.lists for insert to authenticated
with check (created_by=(select auth.uid())
  and private.is_space_member(space_id));
create policy "Edit visible list" on public.lists for update to authenticated
using (private.is_space_member(space_id)
  and (visibility='shared' or created_by=(select auth.uid())))
with check (private.is_space_member(space_id)
  and (visibility='shared' or created_by=(select auth.uid())));

-- RLS of parent lists is evaluated by the subquery below, including privacy.
create policy "Visible list items" on public.list_items for select to authenticated
using (exists (select 1 from public.lists parent where parent.id=list_id));
create policy "Add items to visible list" on public.list_items for insert to authenticated
with check (created_by=(select auth.uid()) and
  exists (select 1 from public.lists parent
    where parent.id=list_id and parent.archived_at is null));
create policy "Edit visible list items" on public.list_items for update to authenticated
using (exists (select 1 from public.lists parent where parent.id=list_id))
with check (exists (select 1 from public.lists parent where parent.id=list_id));

create policy "Visible notes" on public.notes for select to authenticated
using (private.is_space_member(space_id)
  and (visibility='shared' or created_by=(select auth.uid())));
create policy "Create note in my space" on public.notes for insert to authenticated
with check (created_by=(select auth.uid())
  and private.is_space_member(space_id));
create policy "Edit visible note" on public.notes for update to authenticated
using (private.is_space_member(space_id)
  and (visibility='shared' or created_by=(select auth.uid())))
with check (private.is_space_member(space_id)
  and (visibility='shared' or created_by=(select auth.uid())));

revoke all on public.lists,public.list_items,public.notes from anon,authenticated;
grant select on public.lists,public.list_items,public.notes to authenticated;
grant insert(space_id,created_by,title,kind,visibility)
  on public.lists to authenticated;
grant update(title,archived_at) on public.lists to authenticated;
grant insert(list_id,created_by,label,quantity,unit,note,checked)
  on public.list_items to authenticated;
grant update(label,quantity,unit,note,checked,removed_at)
  on public.list_items to authenticated;
grant insert(space_id,created_by,title,body,visibility,pinned)
  on public.notes to authenticated;
grant update(title,body,pinned,archived_at) on public.notes to authenticated;

alter publication supabase_realtime add table public.lists;
alter publication supabase_realtime add table public.list_items;
alter publication supabase_realtime add table public.notes;

