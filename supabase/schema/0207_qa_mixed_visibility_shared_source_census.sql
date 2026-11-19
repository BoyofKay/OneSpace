-- QA 0207: recipient-scoped source census of SHARED rows in the 42
-- private/shared table families. Counts/hashes only, no archival bytes.
create or replace function private.qa_mixed_shared_source_census()
returns jsonb language plpgsql stable security definer set search_path='' as $fn$
declare
 me uuid:=auth.uid(); sid uuid;
 cfg record;
 tab text; join_sql text; guard_sql text; sanitized_sql text;
 n bigint; bad bigint; total bigint:=0;
 records jsonb;
 results jsonb:='[]'::jsonb;
 standard_roots text[]:=array[
 'activities','daily_checkins','goals','items_to_sort','memories',
 'notes','occasion_plans','places','reminders','saved_contacts',
 'shared_trips','space_counters','space_events','tasks'];
 pending_tables text[]:=array[
 'couple_letters','item_links','place_visits','record_action_history'];
 processed int:=0;
begin
 if me is null then raise exception 'Sign in required';end if;
 if (select count(*) from public.space_members where user_id=me)<>1
 then raise exception 'Exactly one active relationship required';end if;
 select space_id into sid from public.space_members where user_id=me;
 if (private.qa_archive_catalog_coverage()->>'classification_complete')<>'true'
 or (select count(*) from private.qa_archive_table_policy
    where approved and disposition='private_shared')<>42
 then raise exception 'Mixed-visibility shared source scope needs review';end if;

 foreach tab in array standard_roots loop
  execute format(
    'select count(*),count(*) filter(where not exists(
      select 1 from public.space_members sm where sm.space_id=$1
        and sm.user_id=r.created_by)),
      coalesce(jsonb_agg(private.qa_structured_value(to_jsonb(r))
        order by r.id),''[]''::jsonb)
       from public.%I r where r.space_id=$1 and r.visibility=''shared''',
    tab)
  into n,bad,records using sid;
  if bad>0 then raise exception 'Shared root original-owner mismatch: %',tab;end if;
  if n>500 or octet_length(convert_to(records::text,'UTF8'))>2097152
  then raise exception 'Shared root census exceeds limit: %',tab;end if;
  total:=total+n; processed:=processed+1;
  results:=results||jsonb_build_array(jsonb_build_object(
   'source_table',tab,'visible_shared_rows',n,
   'source_sha256',encode(extensions.digest(
       convert_to(records::text,'UTF8'),'sha256'),'hex')));
 end loop;

 -- Letters become shared only once genuinely sent and eligible for opening.
 select count(*),count(*) filter(where not exists(select 1 from public.space_members sm
     where sm.space_id=sid and sm.user_id=l.author_id)),
   coalesce(jsonb_agg(private.qa_structured_value(to_jsonb(l))-'reply_to'
     order by l.id),'[]'::jsonb)
 into n,bad,records from public.couple_letters l
 where l.space_id=sid and l.status='sent'
   and (l.open_on is null or l.open_on<=current_date);
 if bad>0 then raise exception 'Shared sent letter original author mismatch';end if;
 if n>500 then raise exception 'Opened letters exceed census limit';end if;
 total:=total+n;processed:=processed+1;
 results:=results||jsonb_build_array(jsonb_build_object(
   'source_table','couple_letters','visible_shared_rows',n,
   'source_sha256',encode(extensions.digest(
     convert_to(records::text,'UTF8'),'sha256'),'hex')));

 -- Place visits have their own space_id but inherit visibility from place.
 select count(*),count(*) filter(where
    v.space_id<>sid
    or not exists(select 1 from public.space_members sm
      where sm.space_id=sid and sm.user_id=p.created_by)
    or not exists(select 1 from public.space_members sm
      where sm.space_id=sid and sm.user_id=v.created_by)),
   coalesce(jsonb_agg(private.qa_structured_value(to_jsonb(v))-'memory_id'
     order by v.id),'[]'::jsonb)
 into n,bad,records from public.place_visits v
 join public.places p on p.id=v.place_id
 where p.space_id=sid and p.visibility='shared';
 if bad>0 then raise exception 'Shared place visits have foreign creator or space';end if;
 if n>500 then raise exception 'Shared place visits exceed census limit';end if;
 total:=total+n;processed:=processed+1;
 results:=results||jsonb_build_array(jsonb_build_object(
  'source_table','place_visits','visible_shared_rows',n,
  'source_sha256',encode(extensions.digest(
     convert_to(records::text,'UTF8'),'sha256'),'hex')));

 -- A polymorphic link is shared ONLY when both endpoints are independently
 -- pair-shared, no matter which partner authored it. Private-linked records
 -- are counted in their owner's separate private source census.
 select count(*),count(*) filter(where
     not exists(select 1 from public.space_members sm
       where sm.space_id=sid and sm.user_id=l.created_by)),
   coalesce(jsonb_agg(private.qa_structured_value(to_jsonb(l))
      order by l.id),'[]'::jsonb)
 into n,bad,records from public.item_links l where l.space_id=sid
 and private.qa_portable_target_scope(l.from_kind,l.from_id,sid,me)='shared'
 and private.qa_portable_target_scope(l.to_kind,l.to_id,sid,me)='shared';
 if bad>0 then raise exception 'Shared item link author not original partner';end if;
 if n>500 then raise exception 'Shared item links exceed census limit';end if;
 total:=total+n;processed:=processed+1;
 results:=results||jsonb_build_array(jsonb_build_object(
  'source_table','item_links','visible_shared_rows',n,
  'source_sha256',encode(extensions.digest(
     convert_to(records::text,'UTF8'),'sha256'),'hex')));

 -- Old shared audit events are reference history. A private archived
 -- experience comment is author-readable only, NOT portable private data.
 select count(*),count(*) filter(where h.actor_id is not null
     and not exists(select 1 from public.space_members sm
       where sm.space_id=sid and sm.user_id=h.actor_id)),
   coalesce(jsonb_agg(private.qa_structured_value(to_jsonb(h))
       order by h.id),'[]'::jsonb)
 into n,bad,records from public.record_action_history h
 where h.space_id=sid and (
  private.qa_action_history_record_scope(
    h.record_kind,h.record_id,sid,me)='shared'
  or (h.record_kind='experience_comment' and
    private.qa_action_history_record_scope(
       h.record_kind,h.record_id,sid,me)='private'));
 if bad>0 then raise exception 'Shared action audit actor outside original pair';end if;
 if n>500 then raise exception 'Shared action history exceeds census limit';end if;
 total:=total+n;processed:=processed+1;
 results:=results||jsonb_build_array(jsonb_build_object(
  'source_table','record_action_history','visible_shared_rows',n,
  'source_sha256',encode(extensions.digest(
     convert_to(records::text,'UTF8'),'sha256'),'hex')));

 -- 22 dependent families with direct private/shared parent roots.
 for cfg in select * from (values
  ('activity_comments','activities','activity_id','author_id'),
  ('activity_component_reactions','activities','activity_id','user_id'),
  ('activity_component_revisions','activities','activity_id','changed_by'),
  ('activity_components','activities','activity_id','created_by'),
  ('activity_decisions','activities','activity_id','created_by'),
  ('activity_revisions','activities','activity_id','changed_by'),
  ('note_references','notes','note_id','created_by'),
  ('occasion_budget_items','occasion_plans','plan_id','created_by'),
  ('occasion_budget_log','occasion_plans','plan_id','actor_id'),
  ('occasion_plan_revisions','occasion_plans','plan_id','changed_by'),
  ('occasion_plan_steps','occasion_plans','plan_id','created_by'),
  ('occasion_proposals','occasion_plans','plan_id','created_by'),
  ('reminder_actions','reminders','reminder_id','actor_id'),
  ('reminder_recipients','reminders','reminder_id','recipient_id'),
  ('saved_contact_revisions','saved_contacts','contact_id','changed_by'),
  ('scrapbook_pages','memories','memory_id','created_by'),
  ('task_checklist_checks','tasks','task_id','user_id'),
  ('task_checklist_items','tasks','task_id','created_by'),
  ('trip_flight_options','shared_trips','trip_id','created_by'),
  ('trip_items','shared_trips','trip_id','created_by'),
  ('trip_messages','shared_trips','trip_id','created_by'),
  ('trip_revisions','shared_trips','trip_id','changed_by')
 ) as parts(table_name,parent_table,parent_fk,author_col)
 loop
  tab:=cfg.table_name;
  join_sql:=format(' from public.%I c join public.%I p on p.id=c.%I
    where p.space_id=$1 and p.visibility=''shared''',
    tab,cfg.parent_table,cfg.parent_fk);
  guard_sql:=format('not exists(select 1 from public.space_members sm
      where sm.space_id=$1 and sm.user_id=p.created_by)
      or (c.%I is not null and not exists(
       select 1 from public.space_members sm
        where sm.space_id=$1 and sm.user_id=c.%I))',
      cfg.author_col,cfg.author_col);
  if tab='scrapbook_pages' then
    guard_sql:=guard_sql||' or (c.updated_by is not null and not exists(
     select 1 from public.space_members sm
     where sm.space_id=$1 and sm.user_id=c.updated_by))';
  elsif tab='reminder_actions' then
    guard_sql:=guard_sql||' or not exists(select 1 from public.space_members sm
       where sm.space_id=$1 and sm.user_id=c.recipient_id)';
  elsif tab='note_references' then
    guard_sql:=guard_sql||'
      or private.qa_portable_target_scope(c.target_kind,c.target_id,p.space_id,$2)<>''shared''';
  elsif tab='task_checklist_checks' then
    guard_sql:=guard_sql||' or not exists(
       select 1 from public.task_checklist_items i
       where i.id=c.item_id and i.task_id=p.id)';
  elsif tab='occasion_budget_log' then
    guard_sql:=guard_sql||' or (c.item_id is not null and not exists(
      select 1 from public.occasion_budget_items i
      where i.id=c.item_id and i.plan_id=p.id))';
  elsif tab='occasion_plan_revisions' then
    guard_sql:=guard_sql||' or (c.record_kind=''plan'' and c.record_id<>p.id)
      or (c.record_kind=''step'' and not exists(
       select 1 from public.occasion_plan_steps st
       where st.id=c.record_id and st.plan_id=p.id))';
  elsif tab='occasion_budget_items' then
    guard_sql:=guard_sql||' or (c.source_activity_id is not null
      and not exists(select 1 from public.activities a
       where a.id=c.source_activity_id and a.space_id=p.space_id
         and a.visibility=''shared''))';
  end if;
  sanitized_sql:='private.qa_structured_value(to_jsonb(c))';
  if tab='occasion_budget_items' then
    sanitized_sql:=sanitized_sql||'-''source_activity_id''-''source_component_id''';
  elsif tab='reminder_recipients' then
    sanitized_sql:=sanitized_sql||'-''next_alert_at''-''snoozed_until''-''last_notified_at''';
  elsif tab='reminder_actions' then
    sanitized_sql:=sanitized_sql||'-''next_alert_at''';
  elsif tab='note_references' then
    sanitized_sql:=sanitized_sql||'-''target_id''';
  elsif tab='scrapbook_pages' then
    sanitized_sql:=sanitized_sql||'-''photo_1_id''-''photo_2_id''-''photo_3_id''-''photo_4_id''';
  end if;
  execute 'select count(*),count(*) filter(where ('||guard_sql||')),
    coalesce(jsonb_agg('||sanitized_sql||'
      order by to_jsonb(c)::text),''[]''::jsonb)'||join_sql
    into n,bad,records using sid,me;
  if bad>0 then
    raise exception 'Mixed shared child ownership or link mismatch: %',tab;
  end if;
  if n>500 or octet_length(convert_to(records::text,'UTF8'))>2097152 then
    raise exception 'Mixed shared child source exceeds cap: %',tab;
  end if;
  total:=total+n;processed:=processed+1;
  results:=results||jsonb_build_array(jsonb_build_object(
    'source_table',tab,'visible_shared_rows',n,
    'source_sha256',encode(extensions.digest(
       convert_to(records::text,'UTF8'),'sha256'),'hex')));
 end loop;

 -- Open-eligible letters' read receipts only, not draft/future events.
 select count(*) into bad from public.couple_letter_reads read
 join public.couple_letters letter on letter.id=read.letter_id
 where letter.space_id=sid and (
   letter.status<>'sent' or
   (letter.open_on is not null and letter.open_on>current_date)
   or read.reader_id=letter.author_id
   or not exists(select 1 from public.space_members sm
     where sm.space_id=sid and sm.user_id=read.reader_id));
 if bad>0 then raise exception 'Mixed shared Love Letter read receipts inconsistent';end if;
 select count(*),
   coalesce(jsonb_agg(private.qa_structured_value(to_jsonb(read))
     order by read.letter_id,read.reader_id),'[]'::jsonb)
 into n,records from public.couple_letter_reads read
 join public.couple_letters letter on letter.id=read.letter_id
 where letter.space_id=sid and letter.status='sent'
   and (letter.open_on is null or letter.open_on<=current_date)
   and exists(select 1 from public.space_members sm
     where sm.space_id=sid and sm.user_id=letter.author_id);
 if n>500 then raise exception 'Letter read receipts over cap';end if;
 total:=total+n;processed:=processed+1;
 results:=results||jsonb_build_array(jsonb_build_object(
  'source_table','couple_letter_reads','visible_shared_rows',n,
  'source_sha256',encode(extensions.digest(
     convert_to(records::text,'UTF8'),'sha256'),'hex')));

 -- Proposal-item joins require the same shared plan and budget item.
 select count(*),
   count(*) filter(where item.plan_id<>p.id
     or not exists(select 1 from public.space_members sm
       where sm.space_id=sid and sm.user_id=proposal.created_by)
     or not exists(select 1 from public.space_members sm
       where sm.space_id=sid and sm.user_id=item.created_by)),
   coalesce(jsonb_agg(private.qa_structured_value(to_jsonb(link))
     order by link.proposal_id,link.item_id),'[]'::jsonb)
 into n,bad,records from public.occasion_proposal_items link
 join public.occasion_proposals proposal on proposal.id=link.proposal_id
 join public.occasion_plans p on p.id=proposal.plan_id
 join public.occasion_budget_items item on item.id=link.item_id
 where p.space_id=sid and p.visibility='shared';
 if bad>0 then raise exception 'Mixed shared occasion proposal item crosses plan or owner';end if;
 if n>500 then raise exception 'Shared proposal links over census cap';end if;
 total:=total+n;processed:=processed+1;
 results:=results||jsonb_build_array(jsonb_build_object(
   'source_table','occasion_proposal_items','visible_shared_rows',n,
   'source_sha256',encode(extensions.digest(
     convert_to(records::text,'UTF8'),'sha256'),'hex')));
 if processed<>42 or jsonb_array_length(results)<>42 then
    raise exception 'Mixed shared source coverage incomplete: %',processed;end if;
 if total>15000 then raise exception 'Mixed shared source record count over cap';end if;
 return jsonb_build_object(
   'schema','onespace.qa.mixed-visibility-shared-source-census.v1',
   'recipient_id',me,'source_space_id',sid,
   'mixed_visibility_table_types_checked',42,
   'visible_shared_rows_counted',total,
   'per_table',results,
   'source_of_truth_counted',true,
   'source_snapshots_persisted',false,
   'complete_encrypted_archive_issued',false,
   'can_restore',false,'safe_to_archive',false,'safe_to_separate',false,
   'warning','Counts/hashes cover shared records in 42 mixed-visibility families for current original pair. No archived bytes, signed source manifest or trusted restoration exist.'
 );
end $fn$;
revoke all on function private.qa_mixed_shared_source_census()
 from public,anon,authenticated;
grant execute on function private.qa_mixed_shared_source_census()
 to authenticated;
create or replace function public.qa_mixed_shared_source_census()
returns jsonb language sql stable security invoker set search_path='' as $fn$
 select private.qa_mixed_shared_source_census()
$fn$;
revoke all on function public.qa_mixed_shared_source_census()
 from public,anon;
grant execute on function public.qa_mixed_shared_source_census()
 to authenticated;
