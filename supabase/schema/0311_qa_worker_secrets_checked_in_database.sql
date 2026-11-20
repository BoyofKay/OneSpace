-- QA only (ugwrpeduzyzrujkizqfo). Never apply to Production.
-- QA workers check their secret against Vault through this service-only
-- function, so no Edge Function dashboard secrets are needed. The finalizer
-- also needs the Vault activation flag below (its explicit second switch).
create or replace function public.qa_worker_secret_matches(p_name text,p_value text)
returns boolean language sql stable security definer set search_path='' as $f$
 select p_name in ('onespace_qa_auth_finalizer_secret','onespace_qa_account_purge_secret',
                   'onespace_qa_media_purge_secret','onespace_qa_allow_auth_finalization')
   and coalesce(length(p_value),0)>=32
   and exists(select 1 from vault.decrypted_secrets
               where name=p_name and decrypted_secret=p_value);
$f$;
revoke all on function public.qa_worker_secret_matches(text,text) from public,anon,authenticated;
grant execute on function public.qa_worker_secret_matches(text,text) to service_role;

do $v$
begin
 if not exists(select 1 from vault.secrets where name='onespace_qa_allow_auth_finalization') then
  perform vault.create_secret('ENABLED_AFTER_ACCEPTANCE_QA_ACCOUNT_FINALIZER',
    'onespace_qa_allow_auth_finalization','QA account finalizer activation switch');
 end if;
end $v$;
