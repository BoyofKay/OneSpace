-- QA only (ugwrpeduzyzrujkizqfo). Never apply to Production.
-- Turns on 7-day account deletion in QA and schedules its workers:
--  * every 5 min: shared-media purge (files of separated couples),
--  * every 5 min: due-account private-media purge,
--  * every 5 min: due-account dispatcher -> finalizer per due account.
-- Worker secrets live in Vault; cron jobs only hold the lookup expression.
-- At the deadline, the leaving account's open invitations are revoked.

-- 1. Worker secrets (created once, random).
do $v$
declare n text;
begin
 foreach n in array array['onespace_qa_auth_finalizer_secret',
   'onespace_qa_account_purge_secret','onespace_qa_media_purge_secret'] loop
  if not exists(select 1 from vault.secrets where name=n) then
   perform vault.create_secret(
     replace(gen_random_uuid()::text,'-','')||replace(gen_random_uuid()::text,'-',''),
     n,'OneSpace QA lifecycle worker secret');
  end if;
 end loop;
end $v$;

-- 2. Dispatcher: revoke open invitations of due accounts, then ask the
-- finalizer to process each one (idempotent; it re-runs until complete).
create or replace function private.qa_dispatch_due_account_deletions()
returns integer language plpgsql security definer set search_path='' as $f$
declare r record; n integer:=0;
begin
 if not exists(select 1 from private.qa_account_v2_gate where id=1 and enabled) then
  return 0;
 end if;
 for r in select user_id from public.account_deletion_requests
   where cancelled_at is null and completed_at is null and purge_after<=now()
   order by purge_after limit 10 loop
  update public.space_invitations
     set revoked_at=now(), delivery_status='revoked'
   where invited_by=r.user_id and accepted_at is null and revoked_at is null;
  perform net.http_post(
    url:='https://ugwrpeduzyzrujkizqfo.supabase.co/functions/v1/onespace-qa-account-finalizer',
    headers:=jsonb_build_object('Content-Type','application/json',
      'x-onespace-qa-auth-finalizer-secret',
      (select decrypted_secret from vault.decrypted_secrets
        where name='onespace_qa_auth_finalizer_secret' limit 1)),
    body:=jsonb_build_object('user_id',r.user_id),
    timeout_milliseconds:=30000);
  n:=n+1;
 end loop;
 return n;
end $f$;
revoke all on function private.qa_dispatch_due_account_deletions() from public,anon,authenticated;

-- 3. Schedules (replace if present).
do $c$
declare j text;
begin
 foreach j in array array['onespace-qa-shared-media-purge',
   'onespace-qa-account-private-media-purge','onespace-qa-due-account-dispatch'] loop
  if exists(select 1 from cron.job where jobname=j) then perform cron.unschedule(j); end if;
 end loop;
 -- The legacy v7 account purge keeps shared content (forbidden by the ADR).
 if exists(select 1 from cron.job where jobname='onespace-account-purge') then
  perform cron.unschedule('onespace-account-purge'); end if;
 perform cron.schedule('onespace-qa-shared-media-purge','*/5 * * * *', $job$
  select net.http_post(
   url:='https://ugwrpeduzyzrujkizqfo.supabase.co/functions/v1/onespace-qa-shared-media-purge',
   headers:=jsonb_build_object('Content-Type','application/json',
    'x-onespace-qa-media-purge-secret',
    (select decrypted_secret from vault.decrypted_secrets
      where name='onespace_qa_media_purge_secret' limit 1)),
   body:='{}'::jsonb, timeout_milliseconds:=30000);
 $job$);
 perform cron.schedule('onespace-qa-account-private-media-purge','*/5 * * * *', $job$
  select net.http_post(
   url:='https://ugwrpeduzyzrujkizqfo.supabase.co/functions/v1/onespace-qa-account-private-media-purge',
   headers:=jsonb_build_object('Content-Type','application/json',
    'x-onespace-qa-account-purge-secret',
    (select decrypted_secret from vault.decrypted_secrets
      where name='onespace_qa_account_purge_secret' limit 1)),
   body:='{}'::jsonb, timeout_milliseconds:=30000);
 $job$);
 perform cron.schedule('onespace-qa-due-account-dispatch','*/5 * * * *',
  $job$ select private.qa_dispatch_due_account_deletions(); $job$);
end $c$;

-- 4. Open the QA account-deletion gate.
update private.qa_account_v2_gate set enabled=true where id=1;
