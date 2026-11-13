-- R16: Preserve existing text memories, add opt-in selfies and scrapbook photos.
alter table public.memories add column if not exists memory_type text
 not null default 'story'
 check (memory_type in ('story','daily_selfie','collage'));
alter table public.memories add column if not exists photo_layout text
 not null default 'grid'
 check (photo_layout in ('grid','feature','polaroid','overlap'));
grant update(memory_type,photo_layout) on public.memories to authenticated;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('onespace-memory-photos','onespace-memory-photos',false,6291456,
 array['image/jpeg','image/png','image/webp'])
on conflict(id) do nothing;

create table public.memory_photos(
 id uuid primary key default gen_random_uuid(),
 memory_id uuid not null references public.memories(id) on delete cascade,
 created_by uuid not null default auth.uid() references auth.users(id),
 caption text not null default '' check(char_length(caption)<=500),
 mime_type text not null check(mime_type in ('image/jpeg','image/png','image/webp')),
 byte_size integer not null check(byte_size between 1 and 6291456),
 object_path text not null unique check(char_length(object_path)<240),
 display_order integer not null default 0,
 archived_at timestamptz,
 created_at timestamptz not null default now(),
 check(object_path ~ '^[0-9a-f-]{36}/[0-9a-f-]{36}/[0-9a-f-]{36}\.(jpg|png|webp)$'),
 check(split_part(object_path,'/',1)=memory_id::text),
 check(split_part(object_path,'/',2)=created_by::text)
);
create index memory_photos_memory_order on public.memory_photos(memory_id,display_order,created_at);
alter table public.memory_photos enable row level security;
create policy "Photos of visible memories" on public.memory_photos
 for select to authenticated using(
  exists(select 1 from public.memories m where m.id=memory_id));
create policy "Owner can add photo to editable memory" on public.memory_photos
 for insert to authenticated with check(created_by=(select auth.uid()) and
  exists(select 1 from public.memories m where m.id=memory_id
    and (m.visibility='shared' or m.created_by=(select auth.uid()))));
create policy "Member can edit photo of collaborative memory" on public.memory_photos
 for update to authenticated using(
  exists(select 1 from public.memories m where m.id=memory_id
    and (m.visibility='shared' or m.created_by=(select auth.uid()))))
 with check(exists(select 1 from public.memories m where m.id=memory_id
    and (m.visibility='shared' or m.created_by=(select auth.uid()))));
revoke all on public.memory_photos from public,anon,authenticated;
grant select on public.memory_photos to authenticated;
grant insert(memory_id,caption,mime_type,byte_size,object_path,display_order)
 on public.memory_photos to authenticated;
grant update(caption,display_order,archived_at) on public.memory_photos to authenticated;

create table public.memory_photo_revisions(
 id bigint generated always as identity primary key,
 photo_id uuid not null references public.memory_photos(id) on delete cascade,
 changed_by uuid references auth.users(id),
 changed_at timestamptz not null default now(),
 before_snapshot jsonb not null,
 after_snapshot jsonb not null
);
alter table public.memory_photo_revisions enable row level security;
create policy "View revisions of visible memory photos"
 on public.memory_photo_revisions for select to authenticated using(
 exists(select 1 from public.memory_photos p where p.id=photo_id));
revoke all on public.memory_photo_revisions from public,anon,authenticated;
grant select on public.memory_photo_revisions to authenticated;

create function private.audit_memory_photo()
returns trigger language plpgsql security definer set search_path='' as $$
begin
 if (old.caption,old.display_order,old.archived_at) is distinct from
    (new.caption,new.display_order,new.archived_at) then
  insert into public.memory_photo_revisions
   (photo_id,changed_by,before_snapshot,after_snapshot)
  values(new.id,auth.uid(),
   jsonb_build_object('caption',old.caption,'order',old.display_order,'archived',old.archived_at),
   jsonb_build_object('caption',new.caption,'order',new.display_order,'archived',new.archived_at));
 end if;
 return new;
end; $$;
create trigger memory_photo_audit after update on public.memory_photos
 for each row execute function private.audit_memory_photo();
revoke all on function private.audit_memory_photo() from public,anon,authenticated;

create function private.memory_id_from_object_path(p text)
returns uuid language sql immutable set search_path='' as $$
 select case when p ~ '^[0-9a-f-]{36}/[0-9a-f-]{36}/[0-9a-f-]{36}\.(jpg|png|webp)$'
  then split_part(p,'/',1)::uuid else null::uuid end;
$$;
revoke all on function private.memory_id_from_object_path(text) from public,anon,authenticated;
grant execute on function private.memory_id_from_object_path(text) to authenticated;

create policy "Upload own photo under editable memory"
on storage.objects for insert to authenticated with check(
 bucket_id='onespace-memory-photos'
 and split_part(name,'/',2)=(select auth.uid())::text
 and exists(select 1 from public.memories m
  where m.id=private.memory_id_from_object_path(name)
   and (m.visibility='shared' or m.created_by=(select auth.uid()))));
create policy "Read photo belonging to visible nonarchived memory"
on storage.objects for select to authenticated using(
 bucket_id='onespace-memory-photos'
 and exists(select 1 from public.memory_photos p
  join public.memories m on m.id=p.memory_id
  where p.object_path=name and p.archived_at is null and m.archived_at is null));
create policy "Remove only own unreferenced memory upload"
on storage.objects for delete to authenticated using(
 bucket_id='onespace-memory-photos'
 and split_part(name,'/',2)=(select auth.uid())::text
 and not exists(select 1 from public.memory_photos p where p.object_path=name)
 and exists(select 1 from public.memories m where m.id=private.memory_id_from_object_path(name)
  and (m.visibility='shared' or m.created_by=(select auth.uid()))));

alter publication supabase_realtime add table public.memory_photos;
