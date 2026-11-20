-- Production prelaunch safety parity with QA: no account/space destruction until
-- verified structured archive/restore and separation are operational.
-- Uploaded media/documents remain excluded by approved product policy.
-- Does not delete or update user content, auth accounts or memberships.
create or replace function public.request_account_deletion()
returns timestamptz
language plpgsql
security invoker
set search_path = ''
as $fn$
begin
  raise exception 'Account deletion is temporarily unavailable until structured archive and space separation are verified';
end;
$fn$;

-- Replace legacy dynamic privilege-elevated export that traversed every
-- public table with user-shaped columns, bypassing RLS and leaking raw metadata.
-- Fail closed until the reviewed explicit per-table export policy can be ported.
create or replace function public.export_my_data()
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $fn$
begin
  raise exception 'Data export is temporarily unavailable until the privacy-scoped export is verified';
end;
$fn$;

-- Future-open private Love Letter existence/date must not be exposed to a
-- partner via the legacy privileged RPC. QA already applies this protection.
create or replace function public.sealed_letters()
returns table(id uuid, author_id uuid, open_on date, sent_at timestamptz)
language sql
stable
security invoker
set search_path = ''
as $fn$
  select null::uuid, null::uuid, null::date, null::timestamptz
  where false;
$fn$;

comment on function public.request_account_deletion()
  is 'Prelaunch fail-closed gate. No account deletion until verified archive/restore and relationship lifecycle.';
comment on function public.export_my_data()
  is 'Prelaunch fail-closed export. Restore a reviewed explicit ownership policy before enabling.';
comment on function public.sealed_letters()
  is 'Suppresses future-open Love Letter metadata; intended contents remain protected until open.';

-- Check after applying: account_deletion_requests pending stays zero;
-- all three functions should be SECURITY INVOKER.
