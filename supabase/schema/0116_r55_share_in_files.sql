-- R55: photos and PDFs shared into OneSpace from other apps land in
-- "Items to sort" with the file attached (private by default, like text shares).
alter table public.items_to_sort
  add column if not exists file_path text check (file_path is null or char_length(file_path) <= 300),
  add column if not exists file_name text check (file_name is null or char_length(file_name) <= 200),
  add column if not exists file_mime text check (file_mime is null or file_mime in
    ('image/jpeg','image/png','image/webp','image/heic','application/pdf')),
  add column if not exists file_size integer check (file_size is null or file_size between 1 and 10485760);
comment on column public.items_to_sort.file_path is
 'R55: object in the onespace-share-in bucket, "<uploader id>/<uuid>.<ext>".';

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values ('onespace-share-in','onespace-share-in',false,10485760,
  array['image/jpeg','image/png','image/webp','image/heic','application/pdf'])
on conflict (id) do update set public=false, file_size_limit=excluded.file_size_limit,
  allowed_mime_types=excluded.allowed_mime_types;

-- Upload only into your own folder.
drop policy if exists "Share-in: upload into my folder" on storage.objects;
create policy "Share-in: upload into my folder" on storage.objects for insert to authenticated
 with check (bucket_id = 'onespace-share-in'
   and (storage.foldername(name))[1] = (select auth.uid())::text);
-- Read when you can see the item it belongs to (yours, or a shared one), or it is your own upload.
drop policy if exists "Share-in: read files of visible items" on storage.objects;
create policy "Share-in: read files of visible items" on storage.objects for select to authenticated
 using (bucket_id = 'onespace-share-in' and (
   (storage.foldername(name))[1] = (select auth.uid())::text
   or exists (select 1 from public.items_to_sort i where i.file_path = storage.objects.name)));
-- Clean-up of a failed save: only your own files.
drop policy if exists "Share-in: remove my own files" on storage.objects;
create policy "Share-in: remove my own files" on storage.objects for delete to authenticated
 using (bucket_id = 'onespace-share-in'
   and (storage.foldername(name))[1] = (select auth.uid())::text);
