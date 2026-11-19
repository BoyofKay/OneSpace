-- QA-only P0 least-privilege hardening.
-- Account deletion is intentionally blocked while archive/restore is incomplete.
-- A function that only throws must not run with SECURITY DEFINER privileges.
alter function public.request_account_deletion() security invoker;
revoke all on function public.request_account_deletion() from public,anon;
grant execute on function public.request_account_deletion() to authenticated;
