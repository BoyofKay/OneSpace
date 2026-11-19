-- QA-only non-destructive media ownership inventory for archive planning.
-- Do not delete original Storage objects or old shared rows.
create table if not exists public.space_media_inventory (
 bucket_id text not null,
 object_path text not null,
 source_table text not null,
 source_id uuid not null,
 source_space_id uuid not null,
 original_visibility text not null
   check(original_visibility in ('private','shared','unclassified')),
 owner_id uuid,
 storage_object_exists boolean not null default true,
 media_sha256 text, -- NULL until actual file bytes are read and hashed
 encrypted_archive_verified boolean not null default false,
 indexed_at timestamptz not null default now(),
 primary key(bucket_id,object_path)
);
create index if not exists space_media_by_space_visibility_idx
 on public.space_media_inventory(source_space_id,original_visibility);
alter table public.space_media_inventory enable row level security;
revoke all on public.space_media_inventory from public,anon,authenticated;

-- All six known media references: photos, notes, trips, comments, and
-- activity image/voice components. No URL strings are treated as file keys.
with referenced as (
 select
 'onespace-memory-photos'::text bucket_id, p.object_path,
 'memory_photos'::text source_table, p.id source_id,
 m.space_id source_space_id,
 case when m.visibility in ('private','shared') then m.visibility
 else 'unclassified' end original_visibility,
 case when m.visibility='private' then m.created_by else null end owner_id
 from public.memory_photos p join public.memories m on m.id=p.memory_id
 where p.object_path is not null

 union all
 select 'onespace-note-images',p.object_path,'note_images',p.id,
 n.space_id,
 case when n.visibility in ('private','shared') then n.visibility
 else 'unclassified' end,
 case when n.visibility='private' then n.created_by else null end
 from public.note_images p join public.notes n on n.id=p.note_id
 where p.object_path is not null

 union all
 select 'onespace-trip-documents',p.object_path,'trip_attachments',p.id,
 t.space_id,
 case when t.visibility in ('private','shared') then t.visibility
 else 'unclassified' end,
 case when t.visibility='private' then t.created_by else null end
 from public.trip_attachments p join public.shared_trips t on t.id=p.trip_id
 where p.object_path is not null

 union all
 select 'onespace-activity-voice',p.voice_path,'activity_comments',p.id,
 a.space_id,
 case when a.visibility in ('private','shared') then a.visibility
 else 'unclassified' end,
 case when a.visibility='private' then a.created_by else null end
 from public.activity_comments p join public.activities a on a.id=p.activity_id
 where p.voice_path is not null

 union all
 select 'onespace-activity-media',p.payload->>'object_path',
 'activity_components',p.id,a.space_id,
 case when a.visibility in ('private','shared') then a.visibility
 else 'unclassified' end,
 case when a.visibility='private' then a.created_by else null end
 from public.activity_components p join public.activities a on a.id=p.activity_id
 where p.kind='image' and nullif(p.payload->>'object_path','') is not null

 union all
 select 'onespace-activity-voice',p.payload->>'voice_path',
 'activity_components',p.id,a.space_id,
 case when a.visibility in ('private','shared') then a.visibility
 else 'unclassified' end,
 case when a.visibility='private' then a.created_by else null end
 from public.activity_components p join public.activities a on a.id=p.activity_id
 where p.kind='voice' and nullif(p.payload->>'voice_path','') is not null
)
insert into public.space_media_inventory
(bucket_id,object_path,source_table,source_id,source_space_id,
 original_visibility,owner_id,storage_object_exists)
select r.bucket_id,r.object_path,r.source_table,r.source_id,r.source_space_id,
 r.original_visibility,r.owner_id,o.id is not null
from referenced r
left join storage.objects o on o.bucket_id=r.bucket_id and o.name=r.object_path
on conflict(bucket_id,object_path) do update set
 original_visibility=excluded.original_visibility,
 owner_id=excluded.owner_id,
 source_space_id=excluded.source_space_id,
 storage_object_exists=excluded.storage_object_exists,
 indexed_at=now();

-- No archive-ready or delete-ready status is granted by this metadata scan.
-- Actual authenticated Storage read, byte count, SHA-256, immutable export,
-- and per-recipient encryption still need verification first.
