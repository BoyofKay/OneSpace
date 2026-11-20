-- QA 0229: old pre-separation archive API and wrong keep-shared
-- account deletion instructions are explicitly retired (no data mutation).
-- The legacy pending jobs can still be cancelled by their original actors.
create or replace function public.request_space_lifecycle_action(p_action text)
returns jsonb language plpgsql set search_path=''
as $fn$
begin
  raise exception 'Old archive preparation is retired. Update OneSpace to the new irreversible shared-content deletion flow. No relationship has changed.';
end
$fn$;

create or replace function public.request_account_deletion()
returns timestamptz language plpgsql set search_path=''
as $fn$
begin
 raise exception 'Account deletion is temporarily disabled while seven-day grace, personal-scope data deletion, partner-private preservation and permanent shared-content erasure are independently verified. No account has been scheduled.';
end
$fn$;

create or replace function public.purge_account_data_service(target uuid)
returns jsonb language plpgsql set search_path=''
as $fn$
begin
 raise exception 'The legacy soft-delete/keep-shared worker is forbidden. Use the verified seven-day private-preserving, shared-erasing replacement after its safety gate is enabled.';
end
$fn$;

-- Read-only information needed to let the requester cancel pre-existing
-- archive preparations. Never imply they authorize irreversible deletions.
create or replace function public.my_space_lifecycle_status()
returns jsonb language sql stable set search_path=''
as $fn$
 select r || jsonb_build_object(
  'archive_policy','retired',
  'safe_to_finalize',false,
  'archives_expected',0,
  'archives_verified',0,
  'reason','Previous non-destructive preparation requests are not executed and cannot be converted to shared-content deletion without fresh irreversible consent'
 )
 from (select private.my_space_lifecycle_status() r) state
$fn$;
