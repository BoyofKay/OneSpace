begin;
do $test$
declare v_owner uuid; report jsonb;
begin
 select sp.created_by into v_owner from public.spaces sp
 where exists(select 1 from public.space_members sm
   where sm.space_id=sp.id and sm.user_id=sp.created_by)
 limit 1;
 if v_owner is null then raise exception 'No QA owner for test'; end if;
 if (select count(*) from private.qa_archive_table_policy
    where approved and relation_kind='root' and disposition='shared_only'
      and source_table in ('shared_experiences','partner_gestures',
        'space_special_dates','space_holiday_sources','spaces'))<>5 then
   raise exception 'Shared-root policy incomplete';
 end if;
 if not exists(select 1 from private.qa_archive_table_policy
     where source_table='couple_letters' and not approved
       and disposition='review_required' and policy_note ilike '%sealed%') then
   raise exception 'Sealed/draft letter was prematurely approved for shared export';
 end if;
 perform set_config('role','authenticated',true);
 perform set_config('request.jwt.claim.sub',v_owner::text,true);
 report:=public.qa_archive_catalog_coverage();
 if report->>'total_tables'<>'69' or
    report->>'approved_table_policies'<>'25' or
    report->>'root_types_pending'<>'12' or
    report->>'dependent_types_pending'<>'32' or
    report->>'safe_to_archive'<>'false' then
   raise exception 'Review counts or fail-closed archive status wrong: %',report;
 end if;
end $test$;
rollback;
select 'PASS: five RLS-shared roots classified; sealed and draft love letters remain protected; all export gates stay blocked' result;
