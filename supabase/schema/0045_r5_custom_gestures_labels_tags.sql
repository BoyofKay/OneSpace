-- Deployed migration 20261113094650 onespace_r5_gesture_templates_labels_tags_inventory
-- OneSpace R5: optional creator-authored affectionate gestures and reusable tags.
create table public.gesture_templates (
 id uuid primary key default gen_random_uuid(),
 space_id uuid not null references public.spaces(id) on delete cascade,
 creator_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
 recipient_id uuid not null references auth.users(id) on delete cascade,
 kind text not null check(kind in ('hug','thinking','smile','morning','goodnight','proud','support')),
 title text not null check(char_length(btrim(title)) between 1 and 60),
 message text not null check(char_length(btrim(message)) between 1 and 240),
 scheduled_moment text check(scheduled_moment in ('morning','after_work','goodnight')),
 created_at timestamptz not null default now(),
 check(creator_id<>recipient_id)
);
create index gesture_templates_creator on public.gesture_templates(creator_id,space_id,created_at desc);
alter table public.gesture_templates enable row level security;
create policy "Only creator may see templates" on public.gesture_templates
for select to authenticated using(creator_id=(select auth.uid()) and private.is_space_member(space_id));
create policy "Creator may add partner templates" on public.gesture_templates
for insert to authenticated with check(
 creator_id=(select auth.uid()) and private.is_space_member(space_id)
 and exists (select 1 from public.space_members m where m.space_id=gesture_templates.space_id
 and m.user_id=gesture_templates.recipient_id));
create policy "Creator may remove templates" on public.gesture_templates
for delete to authenticated using(creator_id=(select auth.uid()) and private.is_space_member(space_id));
revoke all on public.gesture_templates from public,anon,authenticated;
grant select,delete on public.gesture_templates to authenticated;
grant insert(space_id,recipient_id,kind,title,message,scheduled_moment) on public.gesture_templates to authenticated;

alter table public.profiles add column partner_labels text[] not null default '{}';
grant update(partner_labels) on public.profiles to authenticated;
alter table public.profiles add constraint profiles_partner_labels_size
check (coalesce(array_length(partner_labels,1),0) <= 15);

create table public.space_tags (
 id uuid primary key default gen_random_uuid(),
 space_id uuid not null references public.spaces(id) on delete cascade,
 label text not null check(char_length(btrim(label)) between 1 and 50),
 created_by uuid not null default auth.uid() references auth.users(id),
 created_at timestamptz not null default now(),
 unique(space_id,label)
);
create index space_tags_space_name on public.space_tags(space_id,label);
alter table public.space_tags enable row level security;
create policy "Partner can see tags inventory" on public.space_tags
 for select to authenticated using(private.is_space_member(space_id));
create policy "Partner can create tags inventory" on public.space_tags
 for insert to authenticated with check(created_by=(select auth.uid()) and private.is_space_member(space_id));
revoke all on public.space_tags from public,anon,authenticated;
grant select on public.space_tags to authenticated;
grant insert(space_id,label) on public.space_tags to authenticated;
