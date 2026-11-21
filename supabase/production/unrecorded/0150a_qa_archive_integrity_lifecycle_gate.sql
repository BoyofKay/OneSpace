-- Applied to QA on 2026-11-19 (migration 20261119151951,
-- qa_archive_integrity_lifecycle_gate_20261119) but never saved as a schema
-- file. Later files (0152, 0153, 0176, 0221) depend on it. Copied verbatim
-- from QA's migration history so Production replays the same steps.
-- QA service-only non-destructive export gate.
-- Zero lifecycle transitions may proceed until each affected member has a
-- genuinely verified encrypted private and shared archive, and every media
-- asset was validated in the export.
alter table public.space_archives
 add column if not exists encrypted_bytes_verified boolean not null default false;

create or replace function public.space_lifecycle_export_gate_service(
  p_space_id uuid)
returns jsonb language plpgsql stable security invoker set search_path=''
as $$
declare
 members_count integer;
 expected_archives integer;
 verified_archives integer;
 media_total integer;
 media_unverified integer;
begin
 if current_user<>'service_role' then
  raise exception 'Service role only'; end if;
 select count(*) into members_count
 from public.space_members where space_id=p_space_id;
 if members_count<1 or members_count>2 then
  return jsonb_build_object('safe',false,
    'reason','Invalid current member count'); end if;
 expected_archives:=2*members_count;
 select count(distinct (a.recipient_id,a.archive_kind)) into verified_archives
 from public.space_archives a
 where a.old_space_id=p_space_id
   and a.recipient_id in (select user_id from public.space_members
      where space_id=p_space_id)
   and a.archive_kind in ('private','shared')
   and a.encrypted_bytes_verified
   and a.ciphertext_sha256 ~ '^[0-9a-f]{64}$'
   and a.byte_length>0 and a.ready_at is not null
   and a.status in ('ready','purge_due','purged')
   and (a.status<>'purged' or a.explicit_download_confirmed_at is not null)
   and (a.status='purged' or exists(
      select 1 from storage.objects o
      where o.bucket_id='onespace-archives'
        and o.name=a.encrypted_object_path));
 select count(*),count(*) filter(
   where not m.storage_object_exists or not m.encrypted_archive_verified
   or m.original_visibility='unclassified')
 into media_total,media_unverified
 from public.space_media_inventory m where m.source_space_id=p_space_id;
 return jsonb_build_object(
   'safe',verified_archives=expected_archives and media_unverified=0,
   'members',members_count,'archives_expected',expected_archives,
   'archives_verified',verified_archives,'media_total',media_total,
   'media_unverified',media_unverified,
   'reason',case
      when verified_archives<>expected_archives then
      'Missing per-person verified encrypted private/shared archives'
      when media_unverified>0 then
      'Source media has not been verified inside encrypted archives'
      else 'All current export safety conditions passed' end);
end $$;
revoke all on function public.space_lifecycle_export_gate_service(uuid)
 from public,anon,authenticated;
grant execute on function public.space_lifecycle_export_gate_service(uuid)
 to service_role;
