-- No production fixtures; verifies that mobile & website hardening survives a schema reload.
begin;
do $qa$
declare n integer;
begin
 if has_function_privilege('anon','public.log_client_error(text,text,text,text,text)','EXECUTE') then
  raise exception 'Anonymous error logging still executable';
 end if;
 if not has_function_privilege('anon','public.submit_public_support(text,text,text,text,text,text,text,text)','EXECUTE') then
  raise exception 'Pre-login support no longer works';
 end if;
 if (select pg_get_userbyid(proowner) from pg_proc where oid='public.submit_public_support(text,text,text,text,text,text,text,text)'::regprocedure) <> 'onespace_support_writer'
 then raise exception 'Support function owner privileged';end if;
 if (select pg_get_userbyid(proowner) from pg_proc where oid='public.log_client_error(text,text,text,text,text)'::regprocedure) <> 'onespace_error_writer'
 then raise exception 'Error logger function owner privileged';end if;
 if (select rolbypassrls from pg_roles where rolname='onespace_support_writer')
 or (select rolbypassrls from pg_roles where rolname='onespace_error_writer')
 then raise exception 'One of the intake roles bypasses RLS';end if;
 if has_table_privilege('anon','public.public_support_requests','SELECT')
 or has_table_privilege('authenticated','public.client_errors','SELECT')
 then raise exception 'Private support or diagnostics tables publicly readable';end if;
 select count(*) into n from pg_proc p join pg_namespace s on s.oid=p.pronamespace
 where s.nspname='private' and p.prorettype='pg_catalog.trigger'::regtype
 and has_function_privilege('authenticated',p.oid,'EXECUTE');
 if n>0 then raise exception 'Private trigger handlers still directly executable: %',n;end if;
end $qa$;
select 'PASS: intake, diagnostics, private triggers and RLS privileges' result;
rollback;
