-- R25: enable scheduled OneSpace FCM delivery after a verified
-- Firebase HTTP v1 test successfully sent a notification.
-- The worker secret remains encrypted in Supabase Vault: only the lookup
-- SQL expression, never the plaintext value, is stored in the cron job.
do $block$
begin
 if not exists(select 1 from cron.job where jobname='onespace-fcm-push-delivery') then
   perform cron.schedule('onespace-fcm-push-delivery','* * * * *', $job$
     select net.http_post(
       url := 'https://ugwrpeduzyzrujkizqfo.supabase.co/functions/v1/onespace-push-delivery',
       headers := jsonb_build_object(
         'Content-Type','application/json',
         'x-onespace-push-secret',
         (select decrypted_secret from vault.decrypted_secrets
          where name='onespace_push_worker_secret' limit 1)
       ),
       body := '{}'::jsonb,
       timeout_milliseconds := 15000
     );
   $job$);
 end if;
end $block$;
