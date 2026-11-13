-- Deployed 20261113132047
-- R12: a first-class contact, independent of Activities, with an append-only audit.
create table public.saved_contacts(
 id uuid primary key default gen_random_uuid(),
 space_id uuid not null references public.spaces(id) on delete cascade,
 created_by uuid not null default auth.uid() references auth.users(id),
 visibility text not null default 'shared'
   check(visibility in ('private','shared')),
 label text not null check(length(btrim(label)) between 1 and 180),
 payload jsonb not null default '{}'::jsonb,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 archived_at timestamptz,
 purge_eligible_at timestamptz
);
create index saved_contacts_by_space on public.saved_contacts(space_id,created_at desc);
create index saved_contacts_archived on public.saved_contacts(space_id,archived_at) where archived_at is not null;
alter table public.saved_contacts enable row level security;
create policy "View visible contacts in shared space" on public.saved_contacts
 for select to authenticated
 using(private.is_space_member(space_id)
 and (visibility='shared' or created_by=(select auth.uid())));
create policy "Create own contact" on public.saved_contacts
 for insert to authenticated
 with check(created_by=(select auth.uid()) and private.is_space_member(space_id));
create policy "Edit shared contacts or own private contacts" on public.saved_contacts
 for update to authenticated
 using(private.is_space_member(space_id)
 and (visibility='shared' or created_by=(select auth.uid())))
 with check(private.is_space_member(space_id)
 and (visibility='shared' or created_by=(select auth.uid())));
revoke all on public.saved_contacts from public,anon,authenticated;
grant select on public.saved_contacts to authenticated;
grant insert(space_id,created_by,visibility,label,payload) on public.saved_contacts to authenticated;
grant update(label,payload,visibility,archived_at) on public.saved_contacts to authenticated;

create table public.saved_contact_revisions(
 id bigint generated always as identity primary key,
 contact_id uuid not null references public.saved_contacts(id) on delete cascade,
 changed_by uuid references auth.users(id),
 changed_at timestamptz not null default now(),
 change_kind text not null check(change_kind in ('edited','removed','restored')),
 old_label text, new_label text,
 old_payload jsonb, new_payload jsonb,
 old_visibility text, new_visibility text
);
create index saved_contact_revisions_by_contact on public.saved_contact_revisions(contact_id,changed_at desc);
alter table public.saved_contact_revisions enable row level security;
create policy "Read history for contacts I can see"
 on public.saved_contact_revisions for select to authenticated
 using(exists(select 1 from public.saved_contacts c where c.id=contact_id));
revoke all on public.saved_contact_revisions from public,anon,authenticated;
grant select on public.saved_contact_revisions to authenticated;
create function private.audit_saved_contact()
returns trigger language plpgsql security definer set search_path='' as $$
declare change_type text;
begin
 if new.archived_at is null then
   new.purge_eligible_at:=null;
 elsif old.archived_at is null then
   new.purge_eligible_at:=now()+interval '30 days';
 else new.purge_eligible_at:=old.purge_eligible_at;
 end if;
 new.updated_at:=now();
 if (old.label,old.payload,old.visibility,old.archived_at) is distinct from
    (new.label,new.payload,new.visibility,new.archived_at) then
   change_type:=case
     when old.archived_at is null and new.archived_at is not null then 'removed'
     when old.archived_at is not null and new.archived_at is null then 'restored'
     else 'edited' end;
   insert into public.saved_contact_revisions(
      contact_id,changed_by,change_kind,old_label,new_label,
      old_payload,new_payload,old_visibility,new_visibility)
   values(new.id,auth.uid(),change_type,old.label,new.label,
      old.payload,new.payload,old.visibility,new.visibility);
 end if;
 return new;
end;$$;
create trigger saved_contact_revision_before_update
 before update on public.saved_contacts for each row
 execute function private.audit_saved_contact();
alter publication supabase_realtime add table public.saved_contacts;
