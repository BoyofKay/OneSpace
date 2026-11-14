-- R38 Notes 2.0 — first-class links to source objects.
-- Links contain ONLY identifiers. Titles stay in the original RLS-protected
-- record, so a private surprise can never leak through stored link metadata.
create or replace function private.note_reference_visible(
 p_note uuid,p_kind text,p_target uuid
) returns boolean language sql stable security invoker
set search_path='' as $$
 select exists(
  select 1 from public.notes n
  where n.id=p_note and (
   (p_kind='task' and exists(
    select 1 from public.tasks t where t.id=p_target
     and t.space_id=n.space_id
     and (n.visibility='private' or t.visibility='shared')))
   or (p_kind='event' and exists(
    select 1 from public.space_events e where e.id=p_target
     and e.space_id=n.space_id
     and (n.visibility='private' or e.visibility='shared')))
   or (p_kind='occasion' and exists(
    select 1 from public.occasion_plans p where p.id=p_target
     and p.space_id=n.space_id
     and (n.visibility='private' or p.visibility='shared')))
   or (p_kind='experience' and exists(
    select 1 from public.shared_experiences x where x.id=p_target
     and x.space_id=n.space_id))
  )
 );
$$;
revoke all on function private.note_reference_visible(uuid,text,uuid)
 from public,anon;
grant execute on function private.note_reference_visible(uuid,text,uuid)
 to authenticated;

create table if not exists public.note_references (
 id uuid primary key default gen_random_uuid(),
 note_id uuid not null references public.notes(id) on delete cascade,
 target_kind text not null check(
  target_kind in ('task','event','occasion','experience')),
 target_id uuid not null,
 created_by uuid not null default auth.uid() references auth.users(id),
 created_at timestamptz not null default now(),
 unique(note_id,target_kind,target_id)
);
create index if not exists note_references_by_note
 on public.note_references(note_id,created_at,id);
alter table public.note_references enable row level security;

create policy "Read only note links whose source is visible"
 on public.note_references for select to authenticated
 using (private.note_reference_visible(note_id,target_kind,target_id));
create policy "Link only authorized notes and source objects"
 on public.note_references for insert to authenticated
 with check (
  created_by=(select auth.uid()) and
  exists(select 1 from public.notes n where n.id=note_id
   and n.archived_at is null) and
  private.note_reference_visible(note_id,target_kind,target_id)
 );
create policy "Unlink references from accessible notes"
 on public.note_references for delete to authenticated
 using (exists(select 1 from public.notes n where n.id=note_id
  and n.archived_at is null));

revoke all on public.note_references from public,anon,authenticated;
grant select,delete on public.note_references to authenticated;
grant insert(note_id,target_kind,target_id) on public.note_references
 to authenticated;
alter publication supabase_realtime add table public.note_references;
