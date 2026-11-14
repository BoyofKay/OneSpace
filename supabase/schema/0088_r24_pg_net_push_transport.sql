-- R24: provision pg_net for scheduled Edge Function delivery.
-- No schedule is activated until Firebase and the private invocation secret
-- are configured by the project administrator.
create extension if not exists pg_net with schema extensions;
