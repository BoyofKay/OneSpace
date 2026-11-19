begin;
do $qa$
declare member_id uuid; coverage jsonb; n int;
begin
 select user_id into member_id from public.space_members limit 1;
 if member_id is null then raise exception 'QA member fixture unavailable';end if;
 if (select count(*) from private.qa_archive_table_policy where approved)<>69
 or (select count(*) from private.qa_archive_table_policy where not approved)<>0
 then raise exception '69/69 scope classifications were not approved';end if;
 perform set_config('role','authenticated',true);
 perform set_config('request.jwt.claim.sub',member_id::text,true);
 coverage:=public.qa_archive_catalog_coverage();
 if coverage->>'classification_complete'<>'true'
 or (coverage->>'approved_table_policies')::int<>69
 or (coverage->>'root_types_pending')::int<>0
 or (coverage->>'dependent_types_pending')::int<>0
 or coverage->>'safe_to_archive'<>'false'
 or coverage->>'safe_to_separate'<>'false'
 or coverage->>'encrypted_portable_archive_complete'<>'false'
 or coverage->>'trusted_private_restore_complete'<>'false'
 or coverage->>'source_of_truth_cutover_complete'<>'false'
 or coverage->>'reason' not like '%Table classification is complete%'
 then raise exception 'Misleading QA archive readiness: %',coverage;end if;
 perform set_config('role','postgres',true);
 create table public.qa_unclassified_0193_drift (
 id uuid primary key default gen_random_uuid(),
 space_id uuid not null
 );
 perform set_config('role','authenticated',true);
 coverage:=public.qa_archive_catalog_coverage();
 if coverage->>'classification_complete'<>'false'
 or (coverage->>'unregistered_root_types')::int<1
 or coverage->>'safe_to_archive'<>'false'
 or coverage->>'safe_to_separate'<>'false'
 then raise exception 'Future unregistered space table was not blocked: %',coverage;end if;
end $qa$;
rollback;
select 'PASS: 69/69 classification truthful, zero ready encrypted/restore gates, new unregistered schema returns incomplete and remains blocked; rollback' result;