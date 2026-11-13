-- Deployed 20261113132209
-- R12: editable user-specific overrides of built-in gesture messages.
create table public.gesture_message_overrides(
 id uuid primary key default gen_random_uuid(),
 space_id uuid not null references public.spaces(id) on delete cascade,
 owner_id uuid not null default auth.uid() references auth.users(id),
 kind text not null check(kind in ('hug','thinking','smile','morning','goodnight',
 'proud','support','thanks','lucky','miss_together','miss_home','miss_kids','miss_pets')),
 message_index integer not null check(message_index between 0 and 49),
 message text not null check(length(btrim(message)) between 1 and 240),
 disabled boolean not null default false,
 updated_at timestamptz not null default now(),
 unique(owner_id,kind,message_index)
);
alter table public.gesture_message_overrides enable row level security;
create policy "Read my own preset overrides"
 on public.gesture_message_overrides for select to authenticated
 using(owner_id=(select auth.uid()) and private.is_space_member(space_id));
create policy "Create my own preset overrides"
 on public.gesture_message_overrides for insert to authenticated
 with check(owner_id=(select auth.uid()) and private.is_space_member(space_id));
create policy "Edit my own preset overrides"
 on public.gesture_message_overrides for update to authenticated
 using(owner_id=(select auth.uid()) and private.is_space_member(space_id))
 with check(owner_id=(select auth.uid()) and private.is_space_member(space_id));
revoke all on public.gesture_message_overrides from public,anon,authenticated;
grant select on public.gesture_message_overrides to authenticated;
grant insert(space_id,owner_id,kind,message_index,message,disabled)
 on public.gesture_message_overrides to authenticated;
grant update(message,disabled) on public.gesture_message_overrides to authenticated;
