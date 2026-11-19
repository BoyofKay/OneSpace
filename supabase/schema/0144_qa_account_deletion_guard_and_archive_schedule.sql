-- QA guard: the legacy account purge would leave the user's former
-- shared relationship active and bypass verified media-inclusive export.
-- Fail closed until the new archival deletion pipeline is complete.
-- Current QA pending deletion count was verified as zero before this change.
create or replace function public.request_account_deletion()
returns timestamptz language plpgsql security definer set search_path=''
as $$
begin
 raise exception 'Account deletion is temporarily unavailable in QA until secure archive and space separation are verified';
end $$;
create or replace function public.purge_due_accounts_list()
returns setof uuid language sql security definer set search_path=''
as $$select id from auth.users where false$$;
create or replace function public.purge_account_data_service(target uuid)
returns jsonb language plpgsql security definer set search_path=''
as $$
begin
 raise exception 'Legacy account purge disabled in QA: secure archive required';
end $$;

-- Hourly cleanup only for the temporary ENCRYPTED archive bucket.
-- Uses the same established Vault secret as other QA service workers.
select cron.schedule('onespace-archive-janitor','37 * * * *',$job$
  select net.http_post(
    url := 'https://ugwrpeduzyzrujkizqfo.supabase.co/functions/v1/onespace-archive-janitor',
    headers := jsonb_build_object('Content-Type','application/json',
       'x-onespace-push-secret',
       (select decrypted_secret from vault.decrypted_secrets
        where name='onespace_push_worker_secret' limit 1)),
    body := '{}'::jsonb,
    timeout_milliseconds := 60000);
$job$)
where not exists(select 1 from cron.job where jobname='onespace-archive-janitor');
