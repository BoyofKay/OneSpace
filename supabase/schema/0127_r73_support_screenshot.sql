-- R73 (Ahmed): "Report a technical issue" can carry a screenshot.
-- Private bucket; each person writes only in their own folder; the
-- support team reads it in the Supabase dashboard.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('onespace-support', 'onespace-support', false, 6291456,
        array['image/jpeg','image/png','image/webp'])
on conflict (id) do nothing;

alter table public.support_requests
  add column if not exists screenshot_path text check (char_length(screenshot_path) <= 300);
grant insert (screenshot_path) on public.support_requests to authenticated;

create policy "Own support screenshots: upload" on storage.objects for insert to authenticated
  with check (bucket_id = 'onespace-support' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "Own support screenshots: read" on storage.objects for select to authenticated
  using (bucket_id = 'onespace-support' and (storage.foldername(name))[1] = auth.uid()::text);
