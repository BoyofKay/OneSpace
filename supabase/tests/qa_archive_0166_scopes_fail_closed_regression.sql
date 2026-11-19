-- QA-only, no permanent writes. Validate catalog classification and privacy gates.
begin;
do $test$
declare v_owner uuid; j jsonb; n int;
begin
 select s.created_by into v_owner from public.spaces s join public.space_members sm
 on sm.space_id=s.id and sm.user_id=s.created_by limit 1;
 if v_owner is null then raise exception 'QA owner fixture required'; end if;
 if has_function_privilege('anon','public.qa_archive_catalog_coverage()','execute') then
   raise exception 'Anonymous archive coverage unexpectedly available'; end if;
 select count(*) into n from private.qa_archive_table_policy
 where source_table=any(array[
   'calendar_partner_reminders','gesture_message_overrides','gesture_schedules',
   'gesture_templates','object_shares','partner_checkin_requests',
   'space_notifications','space_tags','memory_photo_revisions',
   'occasion_plan_steps','occasion_proposals','shared_experience_interests',
   'shared_experience_reviews','trip_flight_options','trip_items','trip_messages'])
 and approved and disposition<>'review_required';
 if n<>16 then raise exception 'Expected 16 explicitly reviewed policies, got %',n;end if;
 -- Counts are minimum/maximum guards: newer independently reviewed types
 -- must not invalidate this historical regression.
 if (select count(*) from private.qa_archive_table_policy where approved)<41
 or (select count(*) from private.qa_archive_table_policy where not approved)>28 then
   raise exception 'Reviewed archive catalog regressed below QA 0166 baseline';end if;
 if (select count(*) from private.qa_archive_table_policy where
     source_table in ('couple_letters','reminder_actions','reminder_recipients','activity_revisions')
     and approved)>0 then raise exception 'Sensitive unresolved tables unexpectedly approved';end if;
 perform set_config('role','authenticated',true);
 perform set_config('request.jwt.claim.sub',v_owner::text,true);
 j:=public.qa_archive_catalog_coverage();
 if (j->>'safe_to_archive')<>'false'
 or (j->>'safe_to_separate')<>'false'
 or (j->>'classification_complete')<>'false'
 or (j->>'root_types_pending')::int<>4
 or (j->>'dependent_types_pending')::int>24
 or (j->>'media_types_excluded')::int<4 then
  raise exception 'Unexpected QA catalog readiness %', j;end if;
end $test$;
rollback;
select 'PASS: sixteen policies reviewed, four media classes excluded, catalog baseline retained and destructive gates remain CLOSED' as result;
