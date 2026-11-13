-- OneSpace: private voice attachments and conversation messages.
-- Additive: preserves existing texts, contacts, photos and Activity revisions.
insert into storage.buckets
  (id,name,public,file_size_limit,allowed_mime_types)
values ('onespace-activity-voice','onespace-activity-voice',false,5242880,
        array['audio/mp4','audio/x-m4a']::text[])
on conflict (id) do nothing;

alter table public.activity_components
 drop constraint activity_components_kind_check;
alter table public.activity_components
 add constraint activity_components_kind_check
 check (kind in (
  'link','note','option','step','date','price','spec',
  'reminder','tag','mention','location','image','contact','voice'
 ));

alter table public.activity_comments
 add column if not exists voice_path text,
 add column if not exists voice_seconds integer;

alter table public.activity_comments
 add constraint activity_comment_voice_consistency
 check (
   (voice_path is null and voice_seconds is null)
   or (
      voice_path is not null
      and voice_seconds between 1 and 120
      and voice_path like activity_id::text || '/' || author_id::text || '/%'
      and voice_path ~ '\.m4a$'
   )
 );
grant insert(voice_path,voice_seconds) on public.activity_comments to authenticated;

create policy "OneSpace read authorized private voice"
on storage.objects for select to authenticated
using (
 bucket_id = 'onespace-activity-voice'
 and array_length(storage.foldername(name),1) = 2
 and exists (
  select 1 from public.activities a
  where a.id::text = (storage.foldername(name))[1]
 )
);

create policy "OneSpace own voice upload to Activity"
on storage.objects for insert to authenticated
with check (
 bucket_id='onespace-activity-voice'
 and array_length(storage.foldername(name),1)=2
 and (storage.foldername(name))[2]=(select auth.uid())::text
 and storage.extension(name)='m4a'
 and exists (
  select 1 from public.activities a
  where a.id::text=(storage.foldername(name))[1]
    and (a.visibility='shared' or a.created_by=(select auth.uid()))
 )
);

create policy "OneSpace cleanup only unused own voice"
on storage.objects for delete to authenticated
using (
 bucket_id='onespace-activity-voice'
 and array_length(storage.foldername(name),1)=2
 and (storage.foldername(name))[2]=(select auth.uid())::text
 and exists (
  select 1 from public.activities a
  where a.id::text=(storage.foldername(name))[1]
    and (a.visibility='shared' or a.created_by=(select auth.uid()))
 )
 and not exists (
  select 1 from public.activity_components c
  where c.activity_id::text=(storage.foldername(name))[1]
    and c.payload->>'voice_path'=storage.objects.name
 )
 and not exists (
  select 1 from public.activity_comments cm
  where cm.activity_id::text=(storage.foldername(name))[1]
    and cm.voice_path=storage.objects.name
 )
);
