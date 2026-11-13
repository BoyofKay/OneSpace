-- R15 additive private travel document storage. Do not touch accounts, trips or other records.
insert into storage.buckets (id,name,public,file_size_limit,allowed_mime_types)
values ('onespace-trip-documents','onespace-trip-documents',false,10485760,
  array['application/pdf','image/jpeg','image/png','image/webp'])
on conflict (id) do nothing;

create table public.trip_attachments (
 id uuid primary key default gen_random_uuid(),
 trip_id uuid not null references public.shared_trips(id) on delete cascade,
 item_id uuid references public.trip_items(id) on delete set null,
 created_by uuid not null default auth.uid() references auth.users(id),
 title text not null check(char_length(btrim(title)) between 1 and 160),
 kind text not null default 'other' check(kind in
   ('boarding_pass','itinerary','ticket','receipt','photo','other')),
 file_name text not null check(char_length(file_name) between 1 and 200),
 mime_type text not null check(mime_type in
   ('application/pdf','image/jpeg','image/png','image/webp')),
 file_size integer not null check(file_size between 1 and 10485760),
 object_path text not null unique check(char_length(object_path)<240),
 archived_at timestamptz,
 created_at timestamptz not null default now(),
 check(object_path ~ '^[0-9a-f-]{36}/[0-9a-f-]{36}/[0-9a-f-]{36}\.(pdf|jpg|png|webp)$'),
 check(split_part(object_path,'/',1)=trip_id::text),
 check(split_part(object_path,'/',2)=created_by::text)
);
create index trip_attachments_visible on public.trip_attachments(trip_id,created_at desc);
alter table public.trip_attachments enable row level security;

create policy "Only authorized trip viewers may read attachments"
on public.trip_attachments for select to authenticated using (
 exists(select 1 from public.shared_trips t where t.id=trip_id)
);
create policy "Trip members may upload an authorized attachment"
on public.trip_attachments for insert to authenticated with check (
 created_by=(select auth.uid()) and
 exists(select 1 from public.shared_trips t where t.id=trip_id)
 and (item_id is null or exists(
   select 1 from public.trip_items i where i.id=item_id and i.trip_id=trip_id))
);
create policy "Authorized trip collaborators may archive or relabel"
on public.trip_attachments for update to authenticated using (
 exists(select 1 from public.shared_trips t where t.id=trip_id)
) with check (
 exists(select 1 from public.shared_trips t where t.id=trip_id)
 and (item_id is null or exists(
   select 1 from public.trip_items i where i.id=item_id and i.trip_id=trip_id))
);
revoke all on public.trip_attachments from public,anon,authenticated;
grant select on public.trip_attachments to authenticated;
grant insert(trip_id,item_id,title,kind,file_name,mime_type,file_size,object_path)
 on public.trip_attachments to authenticated;
grant update(title,kind,item_id,archived_at)
 on public.trip_attachments to authenticated;

-- An RLS-backed helper checks the trip id without unsafe casting of hostile paths.
create function private.trip_id_from_storage_path(p_path text)
returns uuid language sql immutable set search_path='' as $$
 select case
  when p_path ~ '^[0-9a-f-]{36}/[0-9a-f-]{36}/[0-9a-f-]{36}\.(pdf|jpg|png|webp)$'
    then split_part(p_path,'/',1)::uuid
  else null::uuid end;
$$;
revoke all on function private.trip_id_from_storage_path(text)
 from public,anon,authenticated;
grant execute on function private.trip_id_from_storage_path(text) to authenticated;

create policy "Upload one's own document to a visible trip"
on storage.objects for insert to authenticated with check (
 bucket_id='onespace-trip-documents'
 and split_part(name,'/',2)=(select auth.uid())::text
 and exists(select 1 from public.shared_trips t
   where t.id=private.trip_id_from_storage_path(name))
);
create policy "Read only live documents belonging to visible trips"
on storage.objects for select to authenticated using (
 bucket_id='onespace-trip-documents'
 and exists(select 1 from public.trip_attachments d
   where d.object_path=name and d.archived_at is null)
);
create policy "Remove own orphaned upload only"
on storage.objects for delete to authenticated using (
 bucket_id='onespace-trip-documents'
 and split_part(name,'/',2)=(select auth.uid())::text
 and not exists(select 1 from public.trip_attachments d
   where d.object_path=name)
 and exists(select 1 from public.shared_trips t
   where t.id=private.trip_id_from_storage_path(name))
);
-- No UPDATE or storage object UPSERT permission. Metadata is retained when archived.
