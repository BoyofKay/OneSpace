-- R19 private inline note photo attachments. Existing note bodies unchanged.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('onespace-note-images','onespace-note-images',false,10485760,
 array['image/jpeg','image/png','image/webp']) on conflict(id) do nothing;
create table public.note_images(
 id uuid primary key default gen_random_uuid(),
 note_id uuid not null references public.notes(id) on delete cascade,
 created_by uuid not null default auth.uid() references auth.users(id),
 object_path text not null unique,
 caption text not null default '' check(length(caption)<=300),
 created_at timestamptz not null default now(),
 archived_at timestamptz,
 check(object_path ~ '^[0-9a-f-]{36}/[0-9a-f-]{36}/[0-9a-f-]{36}\.(jpg|png|webp)$'),
 check(split_part(object_path,'/',1)=note_id::text),
 check(split_part(object_path,'/',2)=created_by::text)
);
create index note_images_by_note on public.note_images(note_id,created_at);
alter table public.note_images enable row level security;
create policy "Read images for visible notes" on public.note_images for select to authenticated
 using(exists(select 1 from public.notes n where n.id=note_id));
create policy "Attach photo to editable note" on public.note_images for insert to authenticated
 with check(created_by=(select auth.uid()) and exists(
 select 1 from public.notes n where n.id=note_id and
 (n.visibility='shared' or n.created_by=(select auth.uid()))));
create policy "Archive images for editable note" on public.note_images for update to authenticated
 using(exists(select 1 from public.notes n where n.id=note_id and
 (n.visibility='shared' or n.created_by=(select auth.uid()))))
 with check(exists(select 1 from public.notes n where n.id=note_id and
 (n.visibility='shared' or n.created_by=(select auth.uid()))));
revoke all on public.note_images from public,anon,authenticated;
grant select on public.note_images to authenticated;
grant insert(note_id,object_path,caption) on public.note_images to authenticated;
grant update(caption,archived_at) on public.note_images to authenticated;

create function private.note_id_from_image_path(p text) returns uuid
 language sql immutable set search_path='' as $$
 select case when p ~ '^[0-9a-f-]{36}/[0-9a-f-]{36}/[0-9a-f-]{36}\.(jpg|png|webp)$'
 then split_part(p,'/',1)::uuid else null::uuid end; $$;
revoke all on function private.note_id_from_image_path(text) from public,anon,authenticated;
grant execute on function private.note_id_from_image_path(text) to authenticated;
create policy "Upload own images to accessible note" on storage.objects
 for insert to authenticated with check(
 bucket_id='onespace-note-images' and
 split_part(name,'/',2)=(select auth.uid())::text and
 exists(select 1 from public.notes n where n.id=private.note_id_from_image_path(name)
 and(n.visibility='shared' or n.created_by=(select auth.uid()))));
create policy "Read attached live note photos" on storage.objects
 for select to authenticated using(
 bucket_id='onespace-note-images' and exists(
 select 1 from public.note_images i where i.object_path=name and i.archived_at is null));
create policy "Remove only own orphan note image" on storage.objects
 for delete to authenticated using(
 bucket_id='onespace-note-images' and
 split_part(name,'/',2)=(select auth.uid())::text and
 not exists(select 1 from public.note_images i where i.object_path=name));
alter publication supabase_realtime add table public.note_images;
