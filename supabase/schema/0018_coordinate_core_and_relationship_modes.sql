
-- OneSpace R1: universal Coordinate foundation. Additive migration only.
-- Existing tasks, lists, calendar, memories, notes, goals and check-ins remain untouched.

alter table public.spaces
  add column if not exists relationship_mode text not null default 'not_set'
    check (relationship_mode in
      ('not_set','living_together','apart_same_tz','apart_different_tz')),
  add column if not exists last_met_on date,
  add column if not exists next_meet_on date;
create policy "Space members can update relationship preferences"
on public.spaces for update to authenticated
using (private.is_space_member(id))
with check (private.is_space_member(id));
grant update (relationship_mode,last_met_on,next_meet_on)
on public.spaces to authenticated;

create table public.activities (
 id uuid primary key default gen_random_uuid(),
 space_id uuid not null references public.spaces(id) on delete cascade,
 created_by uuid not null default auth.uid() references auth.users(id),
 title text not null check (char_length(btrim(title)) between 1 and 120),
 body text not null default '' check (char_length(body) <= 12000),
 original_title text not null default '',
 original_body text not null default '',
 visibility text not null default 'shared' check (visibility in ('shared','private')),
 priority text not null default 'normal' check (priority in ('low','normal','high','urgent')),
 due_on date,
 stage text not null default 'exploring'
   check(stage in ('exploring','comparing','decided','purchased','registered',
                    'completed','on_hold','cancelled')),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 archived_at timestamptz
);
create index activities_space_recent on public.activities(space_id,updated_at desc);
create index activities_due_open on public.activities(space_id,due_on)
 where due_on is not null and archived_at is null and stage not in ('completed','cancelled');
alter table public.activities enable row level security;

create function private.activity_keep_origin() returns trigger
language plpgsql set search_path='' as $$
begin
 new.original_title := new.title;
 new.original_body := new.body;
 return new;
end; $$;
create trigger activity_keep_origin before insert on public.activities
for each row execute function private.activity_keep_origin();
create trigger activity_update_clock before update on public.activities
for each row execute function private.touch_note_updated_at();

create policy "Read only visible activities" on public.activities for select to authenticated
 using (private.is_space_member(space_id) and
   (visibility='shared' or created_by=(select auth.uid())));
create policy "Create activities only as self" on public.activities for insert to authenticated
 with check (created_by=(select auth.uid()) and private.is_space_member(space_id));
create policy "Edit shared or owned activities" on public.activities for update to authenticated
 using (private.is_space_member(space_id) and
  (visibility='shared' or created_by=(select auth.uid())))
 with check (private.is_space_member(space_id) and
  (visibility='shared' or created_by=(select auth.uid())));

create table public.activity_revisions (
 id uuid primary key default gen_random_uuid(),
 activity_id uuid not null references public.activities(id) on delete cascade,
 changed_by uuid references auth.users(id),
 old_title text not null,
 new_title text not null,
 old_body text not null,
 new_body text not null,
 old_stage text not null,
 new_stage text not null,
 old_priority text not null,
 new_priority text not null,
 old_due_on date,
 new_due_on date,
 changed_at timestamptz not null default now()
);
create index activity_revisions_by_item on public.activity_revisions(activity_id,changed_at desc);
alter table public.activity_revisions enable row level security;
create policy "Read activity revision history" on public.activity_revisions for select to authenticated
 using (exists(select 1 from public.activities a where a.id=activity_id));
create function private.audit_activity_update() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 if (old.title,old.body,old.stage,old.priority,old.due_on) is distinct from
    (new.title,new.body,new.stage,new.priority,new.due_on) then
  insert into public.activity_revisions
   (activity_id,changed_by,old_title,new_title,old_body,new_body,
    old_stage,new_stage,old_priority,new_priority,old_due_on,new_due_on)
  values(new.id,auth.uid(),old.title,new.title,old.body,new.body,
    old.stage,new.stage,old.priority,new.priority,old.due_on,new.due_on);
 end if;
 return new;
end; $$;
create trigger activity_audit after update on public.activities
for each row execute function private.audit_activity_update();

-- A flexible child component. JSON object payloads are typed by the kind.
-- Every component keeps an immutable parent, creator and initial timestamp.
create table public.activity_components (
 id uuid primary key default gen_random_uuid(),
 activity_id uuid not null references public.activities(id) on delete cascade,
 created_by uuid not null default auth.uid() references auth.users(id),
 kind text not null check(kind in
  ('link','note','option','step','date','price','spec','reminder','tag','mention')),
 label text not null default '' check(char_length(label)<=180),
 payload jsonb not null default '{}'::jsonb
   check(jsonb_typeof(payload)='object' and char_length(payload::text)<=12000),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 archived_at timestamptz,
 unique(activity_id,id)
);
create index activity_components_by_parent on public.activity_components(activity_id,created_at);
alter table public.activity_components enable row level security;
create trigger component_update_clock before update on public.activity_components
for each row execute function private.touch_note_updated_at();
create policy "Read components of visible activities" on public.activity_components
for select to authenticated using(exists(
 select 1 from public.activities a where a.id=activity_id));
create policy "Add components to editable activities" on public.activity_components
for insert to authenticated with check(
 created_by=(select auth.uid()) and exists(
 select 1 from public.activities a where a.id=activity_id and
 (a.visibility='shared' or a.created_by=(select auth.uid()))));
create policy "Edit components in editable activities" on public.activity_components
for update to authenticated
using(exists(select 1 from public.activities a where a.id=activity_id and
 (a.visibility='shared' or a.created_by=(select auth.uid()))))
with check(exists(select 1 from public.activities a where a.id=activity_id and
 (a.visibility='shared' or a.created_by=(select auth.uid()))));

create table public.activity_component_revisions (
 id uuid primary key default gen_random_uuid(),
 activity_id uuid not null,
 component_id uuid not null,
 changed_by uuid references auth.users(id),
 old_label text not null,
 new_label text not null,
 old_payload jsonb not null,
 new_payload jsonb not null,
 changed_at timestamptz not null default now(),
 foreign key(activity_id,component_id)
  references public.activity_components(activity_id,id) on delete cascade
);
create index component_revisions_by_component on public.activity_component_revisions(component_id,changed_at desc);
alter table public.activity_component_revisions enable row level security;
create policy "Read component history when activity visible" on public.activity_component_revisions
for select to authenticated using(exists(
 select 1 from public.activities a where a.id=activity_id));
create function private.audit_component_update() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 if (old.label,old.payload) is distinct from (new.label,new.payload) then
  insert into public.activity_component_revisions
  (activity_id,component_id,changed_by,old_label,new_label,old_payload,new_payload)
  values(new.activity_id,new.id,auth.uid(),
   old.label,new.label,old.payload,new.payload);
 end if;
 return new;
end; $$;
create trigger component_audit after update on public.activity_components
for each row execute function private.audit_component_update();

create table public.activity_comments (
 id uuid primary key default gen_random_uuid(),
 activity_id uuid not null references public.activities(id) on delete cascade,
 component_id uuid,
 reply_to uuid,
 author_id uuid not null default auth.uid() references auth.users(id),
 body text not null check(char_length(btrim(body)) between 1 and 5000),
 created_at timestamptz not null default now(),
 unique(activity_id,id),
 foreign key(activity_id,component_id)
   references public.activity_components(activity_id,id),
 foreign key(activity_id,reply_to)
   references public.activity_comments(activity_id,id)
);
create index activity_comments_chronological on public.activity_comments(activity_id,created_at);
alter table public.activity_comments enable row level security;
create policy "Read activity conversation" on public.activity_comments
for select to authenticated using(exists(
 select 1 from public.activities a where a.id=activity_id));
create policy "Participate in editable activity" on public.activity_comments
for insert to authenticated with check(
 author_id=(select auth.uid()) and exists(
 select 1 from public.activities a where a.id=activity_id
 and (a.visibility='shared' or a.created_by=(select auth.uid()))));

create table public.activity_component_reactions (
 activity_id uuid not null,
 component_id uuid not null,
 user_id uuid not null default auth.uid() references auth.users(id),
 opinion smallint not null check(opinion in (-1,0,1)),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 primary key(component_id,user_id),
 foreign key(activity_id,component_id)
  references public.activity_components(activity_id,id) on delete cascade
);
alter table public.activity_component_reactions enable row level security;
create policy "Read reactions on visible components" on public.activity_component_reactions
for select to authenticated using(exists(
 select 1 from public.activities a where a.id=activity_id));
create policy "React as self to editable components" on public.activity_component_reactions
for insert to authenticated with check(
 user_id=(select auth.uid()) and exists(
 select 1 from public.activities a where a.id=activity_id
 and (a.visibility='shared' or a.created_by=(select auth.uid()))));
create policy "Update only own reactions" on public.activity_component_reactions
for update to authenticated
using(user_id=(select auth.uid()) and exists(
 select 1 from public.activities a where a.id=activity_id and
 (a.visibility='shared' or a.created_by=(select auth.uid()))))
with check(user_id=(select auth.uid()) and exists(
 select 1 from public.activities a where a.id=activity_id and
 (a.visibility='shared' or a.created_by=(select auth.uid()))));
create trigger reaction_update_clock before update on public.activity_component_reactions
for each row execute function private.touch_task_updated_at();

-- Explicit column grants: cannot falsify creator, date, parent, privacy, original,
-- audit history, or another member's reactions.
revoke all on public.activities,public.activity_revisions,public.activity_components,
 public.activity_component_revisions,public.activity_comments,public.activity_component_reactions
 from public,anon,authenticated;
grant select on public.activities,public.activity_revisions,public.activity_components,
 public.activity_component_revisions,public.activity_comments,public.activity_component_reactions
 to authenticated;
grant insert(space_id,title,body,visibility,priority,due_on,stage) on public.activities to authenticated;
grant update(title,body,priority,due_on,stage,archived_at) on public.activities to authenticated;
grant insert(activity_id,kind,label,payload) on public.activity_components to authenticated;
grant update(label,payload,archived_at) on public.activity_components to authenticated;
grant insert(activity_id,component_id,reply_to,body) on public.activity_comments to authenticated;
grant insert(activity_id,component_id,user_id,opinion) on public.activity_component_reactions to authenticated;
grant update(opinion) on public.activity_component_reactions to authenticated;

revoke all on function private.audit_activity_update(),
 private.audit_component_update() from public,anon,authenticated;
alter publication supabase_realtime add table public.activities;
alter publication supabase_realtime add table public.activity_components;
alter publication supabase_realtime add table public.activity_comments;
alter publication supabase_realtime add table public.activity_component_reactions;
