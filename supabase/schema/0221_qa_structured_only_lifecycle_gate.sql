-- 0221: make legacy QA export service contract match approved structured-only archives.
-- Uploaded media and files are never required for archive/restore.
-- Deliberately FAIL CLOSED until full source issuance + private restoration is independently verified.
create or replace function public.space_lifecycle_export_gate_service(p_space_id uuid)
returns jsonb
language plpgsql
stable
set search_path = ''
as $fn$
declare
  members_count integer;
  expected_archives integer;
  verified_archives integer;
begin
  if current_user <> 'service_role' then
    raise exception 'Service role only';
  end if;
  select count(*) into members_count
  from public.space_members m where m.space_id = p_space_id;
  if members_count < 1 or members_count > 2 then
    return jsonb_build_object(
      'safe', false, 'archive_policy','structured_private_shared_no_media_v1',
      'media_included', false, 'documents_included', false,
      'reason', 'Invalid current member count');
  end if;

  expected_archives := 2 * members_count;
  select count(distinct (a.recipient_id,a.archive_kind)) into verified_archives
  from public.space_archives a
  where a.old_space_id = p_space_id
    and a.recipient_id in
       (select m.user_id from public.space_members m where m.space_id = p_space_id)
    and a.archive_kind in ('private','shared')
    and a.encrypted_bytes_verified
    and a.ciphertext_sha256 ~ '^[0-9a-f]{64}$'
    and a.byte_length > 0 and a.ready_at is not null
    and a.status in ('ready','purge_due','purged')
    and (a.status <> 'purged' or a.explicit_download_confirmed_at is not null)
    and (a.status = 'purged' or exists (
       select 1 from storage.objects o
       where o.bucket_id = 'onespace-archives'
         and o.name = a.encrypted_object_path));

  return jsonb_build_object(
    'safe',false,
    'archive_policy','structured_private_shared_no_media_v1',
    'media_included',false,'documents_included',false,
    'members',members_count,
    'archives_expected',expected_archives,
    'archives_verified',verified_archives,
    'structured_source_issuance_verified',false,
    'trusted_private_restore_complete',false,
    'reason','Full structured private/shared archive issuance and trusted private restore are not yet verified. Uploaded media and documents are excluded, not blocking dependencies.');
end;
$fn$;

create or replace function public.space_archive_dependency_inventory()
returns jsonb language sql set search_path = ''
as $fn$
  select jsonb_build_object(
    'has_space',r->'has_space',
    'safe_to_export',false,
    'archive_policy','structured_private_shared_no_media_v1',
    'media_included',false,'documents_included',false,
    'dependent_tables_inspected',r->'dependent_tables_inspected',
    'multi_root_tables',r->'multi_root_tables',
    'reason','Structured dependent ownership and full archive/restore verification remain incomplete. Uploaded media and documents are excluded by design.'
  ) from (select private.space_archive_dependency_inventory() r) audit;
$fn$;
