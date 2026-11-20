savepoint qa_checks;
do $t$
declare s text; ok boolean; failed boolean;
begin
 select decrypted_secret into s from vault.decrypted_secrets where name='onespace_qa_media_purge_secret';
 if not public.qa_worker_secret_matches('onespace_qa_media_purge_secret',s) then
  raise exception 'FAIL 1: right secret refused'; end if;
 if public.qa_worker_secret_matches('onespace_qa_media_purge_secret',s||'x') then
  raise exception 'FAIL 2: wrong secret accepted'; end if;
 if public.qa_worker_secret_matches('onespace_qa_account_purge_secret',s) then
  raise exception 'FAIL 3: secret accepted for another worker'; end if;
 if public.qa_worker_secret_matches('onespace_push_worker_secret',
   (select decrypted_secret from vault.decrypted_secrets where name='onespace_push_worker_secret')) then
  raise exception 'FAIL 4: unrelated Vault secret can be probed'; end if;
 if not public.qa_worker_secret_matches('onespace_qa_allow_auth_finalization',
   'ENABLED_AFTER_ACCEPTANCE_QA_ACCOUNT_FINALIZER') then
  raise exception 'FAIL 5: finalizer activation flag missing'; end if;
 perform set_config('request.jwt.claims',json_build_object('sub',gen_random_uuid(),'role','authenticated')::text,true);
 set local role authenticated;
 failed:=false;
 begin perform public.qa_worker_secret_matches('onespace_qa_media_purge_secret',s);
 exception when others then failed:=true; end;
 if not failed then raise exception 'FAIL 6: app users can call the secret check'; end if;
 reset role;
end $t$;
rollback to savepoint qa_checks;
