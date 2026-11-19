-- QA 0182–0186 final coverage contract: explicit types, current scope,
-- old lifecycle fences and no privilege widening.
begin;
do $guard$
declare
 n int; r jsonb; a uuid;
begin
 select count(*) into n from private.qa_archive_table_policy
 where approved and disposition='private_shared'
  and source_table in (
   'scrapbook_pages','trip_revisions','saved_contact_revisions',
   'activity_comments','activity_component_reactions',
   'activity_component_revisions','activity_components',
   'activity_decisions','activity_revisions',
   'couple_letters','couple_letter_reads','place_visits');
 if n<>12 then raise exception 'Expected 12 newly private/shared-scoped types: %',n;end if;
 select count(*) into n from private.qa_archive_table_policy
 where approved and disposition='shared_only'
 and source_table='partner_checkin_acknowledgements';
 if n<>1 then raise exception 'Check-in acknowledgement policy not shared-only';end if;
 if (select count(*) from private.qa_archive_table_policy where approved)<>60
  or (select count(*) from private.qa_archive_table_policy where not approved)<>9
  or (select count(*) from private.qa_archive_table_policy
    where relation_kind='root' and not approved)<>2
  or (select count(*) from private.qa_archive_table_policy
    where relation_kind='dependent' and not approved)<>7
 then raise exception 'Current QA structured policy totals require review';end if;

 if has_function_privilege('anon',
     'private.qa_nested_written_history_preview(text,uuid)','execute')
  or has_function_privilege('anon',
     'private.qa_activity_nested_structured_preview(uuid)','execute')
  or has_function_privilege('anon',
     'private.qa_love_letter_history_preview(uuid)','execute')
  or has_function_privilege('anon',
     'private.qa_place_visit_history_preview(uuid)','execute')
  or has_function_privilege('anon',
     'private.qa_checkin_ack_history_preview(uuid)','execute')
 then raise exception 'Anonymous private-preview execution was granted';end if;

 select m.user_id into a from public.space_members m limit 1;
 if a is null then raise exception 'QA member fixture missing';end if;
 perform set_config('role','authenticated',true);
 perform set_config('request.jwt.claim.sub',a::text,true);
 r:=public.qa_archive_catalog_coverage();
 if r->>'safe_to_archive'<>'false'
    or r->>'safe_to_separate'<>'false'
    or r->>'classification_complete'<>'false'
    or (r->>'approved_table_policies')::int<>60
    or (r->>'root_types_pending')::int<>2
    or (r->>'dependent_types_pending')::int<>7
 then raise exception 'Archive catalog prematurely authorizes lifecycle: %',r;end if;
end $guard$;
rollback;
select 'PASS: 13 newly approved types, 60/69 total, nine known gaps, anonymous denial, real lifecycle gates still closed; rolled back' result;
