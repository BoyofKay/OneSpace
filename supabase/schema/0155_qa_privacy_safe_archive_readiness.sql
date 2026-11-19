-- QA privacy hardening: client-side readiness must not disclose counts or
-- table-by-table inventory of another member's private records.
-- The private internal audits remain unchanged and fail-closed.
create or replace function public.space_lifecycle_readiness()
returns jsonb language sql security invoker set search_path to ''
as $$
  select jsonb_build_object(
    'has_space',r->'has_space',
    'safe_to_separate',false,
    'role',r->'role',
    'member_count',r->'member_count',
    'space_tables_inspected',r->'space_tables_inspected',
    'archives_expected',r->'archives_expected',
    'archives_verified',r->'archives_verified',
    'storage_reconciliation_pending',r->'storage_reconciliation_pending',
    'reason','Private/shared archive and data-integrity verification is incomplete'
  )
  from (select private.space_lifecycle_readiness() r) audit
$$;

create or replace function public.space_separation_preflight()
returns jsonb language sql security invoker set search_path to ''
as $$ select public.space_lifecycle_readiness() $$;

create or replace function public.space_archive_dependency_inventory()
returns jsonb language sql security invoker set search_path to ''
as $$
  select jsonb_build_object(
    'has_space',r->'has_space',
    'safe_to_export',false,
    'dependent_tables_inspected',r->'dependent_tables_inspected',
    'multi_root_tables',r->'multi_root_tables',
    'reason','Nested data ownership and media-inclusive archive verification remain incomplete'
  ) from (select private.space_archive_dependency_inventory() r) audit
$$;

revoke all on function public.space_lifecycle_readiness(),
  public.space_separation_preflight(),
  public.space_archive_dependency_inventory() from public,anon;
grant execute on function public.space_lifecycle_readiness(),
  public.space_separation_preflight(),
  public.space_archive_dependency_inventory() to authenticated;
