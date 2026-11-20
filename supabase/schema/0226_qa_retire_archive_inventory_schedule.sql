-- QA only: Founder cancelled the archiving feature on 2026-11-20.
-- Stop the scheduled archive source-inventory worker. This makes NO changes
-- to memberships, private/shared content, user accounts, or previous requests.
-- Keep the archive janitor active only to clean any previously staged
-- temporary encrypted preview objects; it does not generate archives.
do $retire$
begin
  if exists(select 1 from cron.job where jobname='onespace-qa-archive-inventory') then
    perform cron.unschedule('onespace-qa-archive-inventory');
  end if;
  if exists(select 1 from cron.job
      where jobname='onespace-qa-archive-inventory' and active) then
    raise exception 'QA archive inventory schedule was not retired';
  end if;
end $retire$;
