-- QA-only catalog regression: unregistered future root + child must fail closed.
begin;
do $test$
declare v_owner uuid; baseline jsonb; after_adding jsonb;
begin
 select sp.created_by into v_owner from public.spaces sp
  where exists(select 1 from public.space_members sm
    where sm.space_id=sp.id and sm.user_id=sp.created_by) limit 1;
 if v_owner is null then raise exception 'No QA space owner'; end if;
 if has_function_privilege('anon','public.qa_archive_catalog_coverage()','execute') then
   raise exception 'Anonymous schema catalog access allowed';
 end if;
 perform set_config('role','authenticated',true);
 perform set_config('request.jwt.claim.sub',v_owner::text,true);
 baseline:=public.qa_archive_catalog_coverage();
 if baseline->>'has_space'<>'true'
  or (baseline->>'total_tables')::int < 60
  or (baseline->>'media_types_excluded')::int<4
  or baseline->>'classification_complete' not in ('true','false'
  )
  or baseline->>'safe_to_archive'<>'false'
  or (baseline->>'unregistered_root_types')::int<>0
  or (baseline->>'unregistered_dependent_types')::int<>0 then
   raise exception 'Incorrect initial archive coverage: %',baseline;
 end if;
 perform set_config('role','postgres',true);
 create table public.qa_m2_untracked_root_trial(
   id uuid primary key default gen_random_uuid(),
   space_id uuid not null references public.spaces(id));
 create table public.qa_m2_untracked_child_trial(
   id uuid primary key default gen_random_uuid(),
   activity_id uuid not null references public.activities(id));
 perform set_config('role','authenticated',true);
 after_adding:=public.qa_archive_catalog_coverage();
 if (after_adding->>'unregistered_root_types')::int<>1
    or (after_adding->>'unregistered_dependent_types')::int<>1
    or after_adding->>'safe_to_archive'<>'false'
    or after_adding->>'classification_complete'<>'false'
    or after_adding->>'safe_to_separate'<>'false' then
   raise exception 'New untracked root/child was not discovered: %',after_adding;
 end if;
end $test$;
rollback;
select 'PASS: catalog discovers known children, denies anonymous access and blocks newly added unclassified root/child; synthetic DDL rolled back' result;
