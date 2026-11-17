-- D77: lets the push / account-purge workers read their shared secret from Vault
-- (service role only), so no extra Edge Function secret has to be typed in.
-- Applied to QA (ugwrpeduzyzrujkizqfo) and Production (letcgxbnblohhfyeuigz) on 17 Nov 2026.
create or replace function public.push_worker_secret() returns text
language sql stable security definer set search_path = '' as $$
  select decrypted_secret from vault.decrypted_secrets where name = 'onespace_push_worker_secret' limit 1;
$$;
revoke all on function public.push_worker_secret() from public, anon, authenticated;
grant execute on function public.push_worker_secret() to service_role;
