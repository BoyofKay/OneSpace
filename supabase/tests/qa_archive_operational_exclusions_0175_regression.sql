-- QA no-write regression for operational archive exclusions.
begin;
do $qa$
declare
  n integer; owner_user uuid; r jsonb;
begin
 select count(*) into n from private.qa_archive_table_policy
 where source_table in ('activity_attention_snoozes','scrapbook_invites')
   and disposition='system_excluded' and approved;
 if n<>2 then raise exception 'Operational privacy exclusions are not enforced';end if;
 if (select count(*) from private.qa_archive_table_policy
      where approved)<>45
    or (select count(*) from private.qa_archive_table_policy
      where not approved)<>24 then
   raise exception 'QA archive catalog unexpectedly changed: review required';end if;
 if (select count(*) from private.qa_archive_table_policy
     where relation_kind='dependent' and not approved)<>20 then
   raise exception 'Unexpected dependent-policy gap after 0175';end if;
 select sp.created_by into owner_user from public.spaces sp
 join public.space_members sm on sm.space_id=sp.id
   and sm.user_id=sp.created_by limit 1;
 if owner_user is null then raise exception 'Paired QA owner fixture missing';end if;
 perform set_config('role','authenticated',true);
 perform set_config('request.jwt.claim.sub',owner_user::text,true);
 r:=public.qa_archive_catalog_coverage();
 if r->>'safe_to_archive'<>'false' or r->>'safe_to_separate'<>'false'
   or r->>'classification_complete'<>'false'
   or (r->>'approved_table_policies')::int<>45
   or (r->>'dependent_types_pending')::int<>20 then
    raise exception 'Archive or lifecycle became prematurely ready: %',r;end if;
end $qa$;
rollback;
select 'PASS: transient snoozes/access grants excluded, 45 of 69 covered, 24 pending; archive and separation remain blocked' as result;
