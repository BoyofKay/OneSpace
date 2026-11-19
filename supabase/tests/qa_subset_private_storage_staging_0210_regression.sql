begin;
do $qa$
declare sid uuid;a uuid;b uuid;x jsonb;r jsonb;idx uuid;keypath text;due jsonb;n int;err text;
begin
select s.id,s.created_by,sm.user_id into sid,a,b
from public.spaces s join public.space_members sm
 on sm.space_id=s.id and sm.user_id<>s.created_by
where (select count(*) from public.space_members v where v.space_id=s.id)=2 limit 1;
if sid is null then raise exception 'Paired QA fixture missing';end if;
if has_function_privilege('anon','public.qa_subset_reserve_service(uuid,uuid)','execute')
 or has_function_privilege('authenticated','public.qa_subset_reserve_service(uuid,uuid)','execute')
 or has_function_privilege('authenticated','public.qa_subset_mark_available_service(uuid,text,integer)','execute')
 or has_function_privilege('authenticated','public.qa_subset_lookup_service(uuid,uuid)','execute')
 or has_function_privilege('authenticated','public.qa_subset_due_purge_service()','execute')
 or has_table_privilege('authenticated','private.qa_vault_subset_staging','select')
then raise exception 'Authenticated or anonymous user can mutate/read internal staging registry';end if;
if not has_function_privilege('service_role','public.qa_subset_reserve_service(uuid,uuid)','execute')
then raise exception 'Edge service role cannot reserve staging';end if;
perform set_config('role','service_role',true);
x:=public.qa_subset_reserve_service(a,sid);
idx:=(x->>'staging_id')::uuid;
keypath:=x->>'object_path';
if keypath<>a::text||'/qa-subsets/'||idx::text||'.osa'
 or x->>'is_verified_archive'<>'false'
 or x->>'can_restore'<>'false' then
 raise exception 'Staging reservation path/scope invalid: %',x;end if;
if public.qa_subset_lookup_service(a,idx)<>'null'::jsonb
 or public.qa_subset_lookup_service(b,idx)<>'null'::jsonb then
 raise exception 'Pending or foreign recipient can fetch file';end if;
if not public.qa_subset_mark_available_service(idx,repeat('a',64),1024)
then raise exception 'Verified file state transition rejected';end if;
if public.qa_subset_mark_available_service(idx,repeat('a',64),1024)
then raise exception 'Staging registry incorrectly allowed replayed verification';end if;
r:=public.qa_subset_lookup_service(a,idx);
if r->>'object_path'<>keypath
 or r->>'ciphertext_sha256'<>repeat('a',64)
 or (r->>'byte_length')::int<>1024
 or r->>'is_verified_archive'<>'false'
 or r->>'can_restore'<>'false' then
 raise exception 'Available subset registry integrity mismatch';end if;
if public.qa_subset_lookup_service(b,idx)<>'null'::jsonb
then raise exception 'Partner could read staged private ciphertext';end if;
begin
 perform public.qa_subset_reserve_service(b,gen_random_uuid());
 raise exception 'Arbitrary space id accepted';
exception when others then
 get stacked diagnostics err=message_text;
 if err<>'QA subset owner/space mismatch' then
 raise exception 'Wrong foreign space error: %',err;end if;
end;
perform public.qa_subset_reserve_service(a,sid);
perform public.qa_subset_reserve_service(a,sid);
begin
 perform public.qa_subset_reserve_service(a,sid);
 raise exception 'Fourth staged object ignored three-object quota';
exception when others then
 get stacked diagnostics err=message_text;
 if err<>'QA subset staging quota exceeded' then
 raise exception 'Unexpected staging quota error: %',err;end if;
end;
perform set_config('role','postgres',true);
update private.qa_vault_subset_staging set expires_at=now()-interval '1 minute'
where id=idx;
perform set_config('role','service_role',true);
if public.qa_subset_lookup_service(a,idx)<>'null'::jsonb
then raise exception 'Expired QA staged ciphertext was still downloadable';end if;
due:=public.qa_subset_due_purge_service();
if not exists(select 1 from jsonb_array_elements(due) e
 where e->>'staging_id'=idx::text and e->>'object_path'=keypath)
then raise exception 'Expired file not listed for safe cleanup';end if;
if not public.qa_subset_finish_purge_service(idx)
then raise exception 'Expired file cleanup registry refused';end if;
if public.qa_subset_finish_purge_service(idx)
then raise exception 'Duplicate purge result marked successful';end if;
perform set_config('role','authenticated',true);
if (public.qa_archive_catalog_coverage()->>'approved_table_policies')::int<>69
or (public.qa_archive_catalog_coverage()->>'classification_complete')<>'true'
then raise exception 'Internal staging table incorrectly expanded 69 source family catalog';end if;
end $qa$;
rollback;
select 'PASS: service-only 24h staged .osa registry, owner path, 3-object quota, anti-replay, verified metadata, partner denial, expired-only purge, public catalog unchanged; rolled back' result;
