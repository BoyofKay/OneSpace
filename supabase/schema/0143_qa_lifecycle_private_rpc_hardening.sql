-- QA lifecycle stage 1 hardening: privileged implementation is private;
-- public RPC endpoints are invoker wrappers and remain authenticated-only.
alter function public.my_space_lifecycle_status() set schema private;
alter function public.request_space_lifecycle_action(text) set schema private;
alter function public.cancel_space_lifecycle_action(uuid) set schema private;

revoke all on function private.my_space_lifecycle_status() from public,anon;
revoke all on function private.request_space_lifecycle_action(text) from public,anon;
revoke all on function private.cancel_space_lifecycle_action(uuid) from public,anon;
grant execute on function private.my_space_lifecycle_status() to authenticated;
grant execute on function private.request_space_lifecycle_action(text) to authenticated;
grant execute on function private.cancel_space_lifecycle_action(uuid) to authenticated;

create function public.my_space_lifecycle_status()
returns jsonb language sql security invoker set search_path to ''
as $$ select private.my_space_lifecycle_status(); $$;
create function public.request_space_lifecycle_action(p_action text)
returns jsonb language sql security invoker set search_path to ''
as $$ select private.request_space_lifecycle_action(p_action); $$;
create function public.cancel_space_lifecycle_action(p_job_id uuid)
returns boolean language sql security invoker set search_path to ''
as $$ select private.cancel_space_lifecycle_action(p_job_id); $$;

revoke all on function public.my_space_lifecycle_status() from public,anon;
revoke all on function public.request_space_lifecycle_action(text) from public,anon;
revoke all on function public.cancel_space_lifecycle_action(uuid) from public,anon;
grant execute on function public.my_space_lifecycle_status() to authenticated;
grant execute on function public.request_space_lifecycle_action(text) to authenticated;
grant execute on function public.cancel_space_lifecycle_action(uuid) to authenticated;