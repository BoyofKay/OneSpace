-- OneSpace R81 / 18 Nov 2026: production-tested least-privilege security hardening.
-- Applied to live OneSpace mobile and website production projects through Supabase migrations.
-- Re-runnable on either schema; never grants direct client read access to private tables.
-- Explicitly public support must remain available BEFORE login.
begin;
do $roles$
begin
 if not exists(select 1 from pg_roles where rolname='onespace_support_writer') then
  create role onespace_support_writer nologin noinherit nobypassrls;
 end if;
 if not exists(select 1 from pg_roles where rolname='onespace_error_writer') then
  create role onespace_error_writer nologin noinherit nobypassrls;
 end if;
end $roles$;
grant onespace_support_writer,onespace_error_writer to postgres;
grant usage,create on schema public to onespace_support_writer,onespace_error_writer;
grant select(created_at,reply_email) on public.public_support_requests to onespace_support_writer;
grant insert(kind,subject,message,reply_email,app_version,platform,locale,diagnostics)
 on public.public_support_requests to onespace_support_writer;
grant select(user_id,created_at) on public.client_errors to onespace_error_writer;
grant insert(user_id,error,stack,context,app_version,platform)
 on public.client_errors to onespace_error_writer;
do $policy$
begin
 if not exists(select 1 from pg_policies where schemaname='public' and tablename='public_support_requests' and policyname='Support intake limited role can check quotas') then
  create policy "Support intake limited role can check quotas" on public.public_support_requests for select to onespace_support_writer using(true);
 end if;
 if not exists(select 1 from pg_policies where schemaname='public' and tablename='public_support_requests' and policyname='Support intake limited role can submit validated requests') then
  create policy "Support intake limited role can submit validated requests" on public.public_support_requests for insert to onespace_support_writer with check(true);
 end if;
 if not exists(select 1 from pg_policies where schemaname='public' and tablename='client_errors' and policyname='Diagnostics limited writer can count its quota') then
  create policy "Diagnostics limited writer can count its quota" on public.client_errors for select to onespace_error_writer using(true);
 end if;
 if not exists(select 1 from pg_policies where schemaname='public' and tablename='client_errors' and policyname='Diagnostics limited writer can insert caller errors') then
  create policy "Diagnostics limited writer can insert caller errors" on public.client_errors for insert to onespace_error_writer with check(
    user_id is not null and user_id=coalesce(
     nullif(pg_catalog.current_setting('request.jwt.claim.sub',true),''),
     nullif(pg_catalog.current_setting('request.jwt.claims',true),'')::jsonb->>'sub')::uuid);
 end if;
end $policy$;
CREATE OR REPLACE FUNCTION public.submit_public_support(p_kind text, p_subject text, p_message text, p_reply_email text, p_app_version text, p_platform text, p_locale text, p_diagnostics text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_kind text:=lower(btrim(coalesce(p_kind,'')));
        v_subject text:=btrim(coalesce(p_subject,''));
        v_message text:=btrim(coalesce(p_message,''));
        v_email text:=lower(btrim(coalesce(p_reply_email,'')));
begin
 if v_kind not in ('contact','account','issue','complaint')
    or char_length(v_subject)>160
    or char_length(v_message) not between 1 and 8000
    or char_length(v_email) not between 5 and 254
    or v_email !~ '^[^[:space:]@]+@[^[:space:]@]+[.][^[:space:]@]+$'
    or char_length(coalesce(p_app_version,''))>40
    or char_length(coalesce(p_platform,''))>32
    or char_length(coalesce(p_locale,''))>16
    or char_length(coalesce(p_diagnostics,''))>4000
 then raise exception 'Invalid support request' using errcode='22023'; end if;
 if not pg_catalog.pg_try_advisory_xact_lock(21427,9111) then
   raise exception 'Support is busy. Please try again shortly.'; end if;
 if (select count(*) from public.public_support_requests where created_at>pg_catalog.now()-interval '1 hour')>=30
 or (select count(*) from public.public_support_requests where lower(reply_email)=v_email and created_at>pg_catalog.now()-interval '1 hour')>=3
 then raise exception 'Too many messages. Please try again later.'; end if;
 insert into public.public_support_requests(kind,subject,message,reply_email,app_version,platform,locale,diagnostics)
 values(v_kind,v_subject,v_message,v_email,p_app_version,p_platform,p_locale,p_diagnostics);
end $function$;
CREATE OR REPLACE FUNCTION public.log_client_error(p_error text, p_stack text, p_context text, p_app_version text, p_platform text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare me uuid:=coalesce(
 nullif(pg_catalog.current_setting('request.jwt.claim.sub',true),''),
 nullif(pg_catalog.current_setting('request.jwt.claims',true),'')::jsonb->>'sub')::uuid;
begin
 if me is null then return; end if;
 if pg_catalog.octet_length(coalesce(p_error,''))>16000 or pg_catalog.octet_length(coalesce(p_stack,''))>32000 then return; end if;
 if not pg_catalog.pg_try_advisory_xact_lock(21427,9112) then return; end if;
 if (select count(*) from public.client_errors where user_id=me and created_at>pg_catalog.now()-interval '1 hour')>=40
 or (select count(*) from public.client_errors where created_at>pg_catalog.now()-interval '1 hour')>=500 then return; end if;
 insert into public.client_errors(user_id,error,stack,context,app_version,platform)
 values(me,left(coalesce(p_error,'?'),1000),left(p_stack,4000),left(p_context,300),left(p_app_version,40),left(p_platform,20));
end $function$;
alter function public.submit_public_support(text,text,text,text,text,text,text,text) owner to onespace_support_writer;
alter function public.log_client_error(text,text,text,text,text) owner to onespace_error_writer;
revoke create on schema public from onespace_support_writer,onespace_error_writer;
revoke all on function public.submit_public_support(text,text,text,text,text,text,text,text) from public;
grant execute on function public.submit_public_support(text,text,text,text,text,text,text,text) to anon,authenticated,service_role;
revoke all on function public.log_client_error(text,text,text,text,text) from public,anon;
grant execute on function public.log_client_error(text,text,text,text,text) to authenticated,service_role;
revoke all on public.public_support_requests,public.client_errors from anon,authenticated;
-- Fail closed on every internal table, including future accidental table grants.
do $denies$
declare target text; ns text; rel text; nm text;
begin
 foreach target in array array['private.app_events','private.founder_attempts','private.founder_couples','private.founder_email_log','private.founder_members','private.founder_spam_counts','private.ops_pending_requests','private.ops_secret_status','private.push_outbox','public.client_errors','public.public_support_requests'] loop
  if to_regclass(target) is null then continue; end if;
  ns := split_part(target,'.',1);
  rel := split_part(target,'.',2);
  nm := 'deny_untrusted_client_access';
  if not exists(select 1 from pg_policies where schemaname=ns and tablename=rel and (policyname=nm or policyname like 'deny_untrusted_clients_%')) then
   execute format('create policy %I on %s as restrictive for all to anon,authenticated using(false) with check(false)',nm,target);
  end if;
 end loop;
end $denies$;
-- SECURITY DEFINER private trigger handlers/internal helpers are not client APIs.
do $lock_private$
declare f record;
begin
 for f in select p.oid::regprocedure sig from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname='private' and
 (p.prorettype='pg_catalog.trigger'::regtype or p.proname in
 ('notice_partner_name','notice_when','occasion_auto_status','occasion_refresh_status','trip_auto_status','trip_refresh_status'))
 loop
  execute format('revoke execute on function %s from public,anon,authenticated',f.sig);
 end loop;
end $lock_private$;
commit;
