-- QA lifecycle: exhaustive read-only readiness audit; privileged implementation stays private.
CREATE OR REPLACE FUNCTION private.space_lifecycle_readiness()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  me uuid := auth.uid();
  sid uuid;
  space_owner uuid;
  member_count integer;
  member_valid boolean;
  t record;
  has_visibility boolean;
  has_creator boolean;
  table_total bigint;
  table_private bigint;
  table_shared bigint;
  total_roots bigint := 0;
  private_roots bigint := 0;
  shared_roots bigint := 0;
  unknown_roots bigint := 0;
  root_tables integer := 0;
  unclassified_tables jsonb := '[]'::jsonb;
  media_inventory_count integer := 0;
  media_unverified integer := 0;
  media_missing_inventory bigint := 0;
  unmatched_storage bigint := 0;
  verified_archives integer := 0;
  archives_expected integer;
  ready boolean;
begin
  if me is null then raise exception 'Sign in required'; end if;
  if (select count(*) from public.space_members where user_id=me) <> 1 then
    return jsonb_build_object('has_space',false,'safe_to_separate',false,
      'reason','No single active space found for this account');
  end if;
  select sm.space_id,s.created_by into sid,space_owner
  from public.space_members sm join public.spaces s on s.id=sm.space_id
  where sm.user_id=me limit 1;
  if sid is null then raise exception 'Space not found'; end if;
  select count(*) into member_count from public.space_members
  where space_id=sid;
  member_valid:=member_count between 1 and 2
    and exists(select 1 from public.space_members where space_id=sid and user_id=space_owner);

  -- Scan every root space-linked table, not just the former fixed list.
  -- Unknown/unclassified records block finalization rather than being discarded.
  for t in
    select c.table_name from information_schema.columns c
    join information_schema.tables tabs
      on tabs.table_schema=c.table_schema and tabs.table_name=c.table_name
    where c.table_schema='public' and c.column_name='space_id'
      and tabs.table_type='BASE TABLE' and c.table_name<>'space_members'
    order by c.table_name
  loop
    root_tables:=root_tables+1;
    select exists(select 1 from information_schema.columns x
      where x.table_schema='public' and x.table_name=t.table_name
        and x.column_name='visibility'), exists(
      select 1 from information_schema.columns x
      where x.table_schema='public' and x.table_name=t.table_name
        and x.column_name='created_by')
    into has_visibility,has_creator;

    if has_visibility and has_creator then
      execute format(
        'select count(*),
          count(*) filter (where visibility=''private'' and
            created_by in (select user_id from public.space_members where space_id=$1)),
          count(*) filter (where visibility=''shared'' and
            created_by in (select user_id from public.space_members where space_id=$1))
         from public.%I where space_id=$1',t.table_name)
      into table_total,table_private,table_shared using sid;
    else
      execute format('select count(*) from public.%I where space_id=$1',t.table_name)
      into table_total using sid;
      table_private:=0;
      table_shared:=0;
    end if;
    total_roots:=total_roots+table_total;
    private_roots:=private_roots+table_private;
    shared_roots:=shared_roots+table_shared;
    unknown_roots:=unknown_roots+table_total-table_private-table_shared;
    if table_total>table_private+table_shared then
      unclassified_tables:=unclassified_tables || to_jsonb(t.table_name);
    end if;
  end loop;

  select count(*),count(*) filter(where not storage_object_exists
     or not encrypted_archive_verified or original_visibility='unclassified')
    into media_inventory_count,media_unverified
  from public.space_media_inventory where source_space_id=sid;

  -- Direct attachment references whose media has not yet been inventoried.
  -- Activity media encoded inside JSON must still be handled by the exporter.
  select
    (select count(*) from public.memory_photos f join public.memories r on r.id=f.memory_id
       where r.space_id=sid and not exists
       (select 1 from public.space_media_inventory v where v.source_space_id=sid
         and v.bucket_id='onespace-memory-photos' and v.object_path=f.object_path))
    +(select count(*) from public.note_images f join public.notes r on r.id=f.note_id
       where r.space_id=sid and not exists
       (select 1 from public.space_media_inventory v where v.source_space_id=sid
         and v.bucket_id='onespace-note-images' and v.object_path=f.object_path))
    +(select count(*) from public.trip_attachments f join public.shared_trips r on r.id=f.trip_id
       where r.space_id=sid and not exists
       (select 1 from public.space_media_inventory v where v.source_space_id=sid
         and v.bucket_id='onespace-trip-documents' and v.object_path=f.object_path))
    +(select count(*) from public.activity_comments f join public.activities r on r.id=f.activity_id
       where r.space_id=sid and f.voice_path is not null and not exists
       (select 1 from public.space_media_inventory v where v.source_space_id=sid
         and v.bucket_id='onespace-activity-voice' and v.object_path=f.voice_path))
    +(select count(*) from public.items_to_sort f
       where f.space_id=sid and f.file_path is not null and not exists
       (select 1 from public.space_media_inventory v where v.source_space_id=sid
         and v.bucket_id='onespace-share-in' and v.object_path=f.file_path))
    into media_missing_inventory;

  -- Candidate leftovers: references stored in JSON are not yet counted here.
  -- They are held for reconciliation, never automatically deleted by this function.
  select count(*) into unmatched_storage
  from storage.objects so
  where so.bucket_id in ('onespace-activity-media','onespace-activity-voice',
    'onespace-memory-photos','onespace-note-images','onespace-trip-documents',
    'onespace-share-in')
   and not exists (select 1 from public.space_media_inventory v
     where v.bucket_id=so.bucket_id and v.object_path=so.name)
   and not exists (select 1 from public.memory_photos x
     where so.bucket_id='onespace-memory-photos' and x.object_path=so.name)
   and not exists (select 1 from public.note_images x
     where so.bucket_id='onespace-note-images' and x.object_path=so.name)
   and not exists (select 1 from public.trip_attachments x
     where so.bucket_id='onespace-trip-documents' and x.object_path=so.name)
   and not exists (select 1 from public.activity_comments x
     where so.bucket_id='onespace-activity-voice' and x.voice_path=so.name)
   and not exists (select 1 from public.items_to_sort x
     where so.bucket_id='onespace-share-in' and x.file_path=so.name);

  archives_expected:=member_count*2;
  select count(distinct (a.recipient_id,a.archive_kind)) into verified_archives
  from public.space_archives a
  where a.old_space_id=sid
    and a.recipient_id in (select user_id from public.space_members where space_id=sid)
    and a.archive_kind in ('private','shared')
    and a.encrypted_bytes_verified
    and a.encrypted_object_path like a.recipient_id::text||'/%'
    and a.ciphertext_sha256 ~ '^[0-9a-f]{64}$'
    and a.byte_length>0 and a.ready_at is not null and a.expires_at>now()
    and a.status in ('ready','purge_due')
    and exists (select 1 from storage.objects so where so.bucket_id='onespace-archives'
      and so.name=a.encrypted_object_path);

  ready:=member_valid and unknown_roots=0
    and media_unverified=0 and media_missing_inventory=0
    and unmatched_storage=0
    and verified_archives=archives_expected;

  return jsonb_build_object(
    'has_space',true,'safe_to_separate',false,
    'root_archive_preconditions_met',ready,
    'role',case when space_owner=me then 'owner' else 'partner' end,
    'member_count',member_count,'members_valid',member_valid,
    'space_tables_inspected',root_tables,'space_linked_records',total_roots,
    'private_root_records',private_roots,'shared_root_records',shared_roots,
    'unclassified_root_records',unknown_roots,
    'unclassified_tables',unclassified_tables,
    'media_inventory_count',media_inventory_count,
    'media_unverified',media_unverified,
    'media_missing_inventory',media_missing_inventory,
    'storage_reconciliation_pending',unmatched_storage>0,
    'archives_expected',archives_expected,'archives_verified',verified_archives,
    'reason',case when not member_valid then 'Space membership integrity must be repaired'
      when unknown_roots>0 then 'Some space records are not classified as private/shared'
      when media_unverified>0 or media_missing_inventory>0 then 'Media inventory and encryption checks are incomplete'
      when unmatched_storage>0 then 'Stored files require reconciliation before separation'
      when verified_archives<>archives_expected then 'Encrypted private/shared archives have not been verified for every member'
      else 'Root and direct-media checks passed; nested dependent records, full archive verification and a transition worker remain pending' end);
end $function$
;
CREATE OR REPLACE FUNCTION public.space_lifecycle_readiness()
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO ''
AS $function$select private.space_lifecycle_readiness()$function$
;
CREATE OR REPLACE FUNCTION private.space_separation_preflight()
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO ''
AS $function$select private.space_lifecycle_readiness()$function$
;
revoke all on function private.space_lifecycle_readiness() from public,anon;
grant execute on function private.space_lifecycle_readiness() to authenticated;
revoke all on function public.space_lifecycle_readiness() from public,anon;
grant execute on function public.space_lifecycle_readiness() to authenticated;
