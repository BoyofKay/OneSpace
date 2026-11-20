-- QA only: schedule source inventory every minute using the existing
-- Vault-backed secret/header convention from the archive janitor.
-- Never duplicate or expose secrets in migration source.
do $cron$
declare original text; replacement text;
begin
 if current_database() is null then raise exception 'No database'; end if;
 select j.command into original from cron.job j
 where j.jobname='onespace-archive-janitor' and j.active;
 if original is null or original not like
   '%/functions/v1/onespace-archive-janitor%' or
   original not like '%x-onespace-push-secret%' then
   raise exception 'Existing Vault-backed QA janitor invocation missing';
 end if;
 replacement:=replace(original,
  '/functions/v1/onespace-archive-janitor',
  '/functions/v1/onespace-qa-archive-inventory');
 if original=replacement then
   raise exception 'Unable to derive inventory cron invocation';
 end if;
 perform cron.schedule('onespace-qa-archive-inventory','* * * * *',replacement);
end $cron$;
