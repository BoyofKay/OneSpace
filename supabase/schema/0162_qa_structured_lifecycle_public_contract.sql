-- QA-only public-facing lifecycle contract aligned with founder-approved
-- structured archives. Uploaded media/documents are excluded from restoration.
-- Keep finalization FALSE until full dependent export/restore is proven.
-- Legacy internal media-inclusive readiness is NOT used to approve separation.

create or replace function public.my_space_lifecycle_status()
returns jsonb language sql security invoker set search_path=''
as $$
  select r || jsonb_build_object(
    'archive_policy','structured_private_shared_no_media_v1',
    'media_included',false,'documents_included',false,
    'safe_to_finalize',false,
    'reason','Structured private/shared archives and restore verification are incomplete; uploaded media and documents are excluded')
  from (select private.my_space_lifecycle_status() r) src
$$;

create or replace function public.space_lifecycle_readiness()
returns jsonb language sql security invoker set search_path=''
as $$
  select jsonb_build_object(
    'has_space',r->'has_space',
    'role',r->'role',
    'member_count',r->'member_count',
    'archive_policy','structured_private_shared_no_media_v1',
    'media_included',false,
    'documents_included',false,
    'archives_expected',r->'archives_expected',
    'archives_verified',r->'archives_verified',
    'safe_to_separate',false,
    'reason','Structured private/shared dependent-record archiving and restoration must be verified before separation; uploaded media and documents are excluded from the archive')
  from (select private.my_space_lifecycle_status() r) src
$$;

create or replace function public.space_separation_preflight()
returns jsonb language sql security invoker set search_path=''
as $$ select public.space_lifecycle_readiness() $$;

revoke all on function public.my_space_lifecycle_status(),
 public.space_lifecycle_readiness(),public.space_separation_preflight()
 from public,anon;
grant execute on function public.my_space_lifecycle_status(),
 public.space_lifecycle_readiness(),public.space_separation_preflight()
 to authenticated;
