-- QA 0200: avoid PL/pgSQL record variable shadowing SQL 'item' alias.
create or replace function private.qa_unmirrored_private_source_census()
returns jsonb language plpgsql stable security definer set search_path='' as $fn$
declare
 me uuid:=auth.uid();
 sid uuid;
 cfg record;
 source_table text;
 parent_table text;
 parent_fk text;
 author_col text;
 sql_where text;
 fault_where text;
 n bigint;
 bad bigint;
 records jsonb;
 fingerprint text;
 result_rows jsonb:='[]'::jsonb;
 total bigint:=0;
 faults bigint:=0;
 expected_types text[]:=array[
  'couple_letters','item_links','place_visits','record_action_history',
  'activity_comments','activity_component_reactions','activity_component_revisions',
  'activity_components','activity_decisions','activity_revisions',
  'couple_letter_reads','note_references','occasion_budget_log',
  'occasion_plan_revisions','occasion_proposal_items','reminder_actions',
  'saved_contact_revisions','scrapbook_pages','trip_revisions'];
begin
 if me is null then raise exception 'Sign in required';end if;
 if (select count(*) from public.space_members sm where sm.user_id=me)<>1
 then raise exception 'Exactly one current space required';end if;
 select sm.space_id into sid from public.space_members sm where sm.user_id=me;
 if (select count(*) from private.qa_archive_table_policy p
     where p.source_table=any(expected_types)
     and p.disposition='private_shared' and p.approved)<>19
 then raise exception 'Private source census table classification changed';end if;
 if (private.qa_archive_catalog_coverage()->>'classification_complete')<>'true'
 then raise exception 'New schema types require archive review';end if;
 for cfg in
  select * from (values
   ('activity_comments','activities','activity_id','author_id'),
   ('activity_component_reactions','activities','activity_id','user_id'),
   ('activity_component_revisions','activities','activity_id','changed_by'),
   ('activity_components','activities','activity_id','created_by'),
   ('activity_decisions','activities','activity_id','created_by'),
   ('activity_revisions','activities','activity_id','changed_by'),
   ('note_references','notes','note_id','created_by'),
   ('occasion_budget_log','occasion_plans','plan_id','actor_id'),
   ('occasion_plan_revisions','occasion_plans','plan_id','changed_by'),
   ('reminder_actions','reminders','reminder_id','actor_id'),
   ('saved_contact_revisions','saved_contacts','contact_id','changed_by'),
   ('scrapbook_pages','memories','memory_id','created_by'),
   ('trip_revisions','shared_trips','trip_id','changed_by')
  ) as kinds(child_table,parent_table,parent_fk,author_col)
 loop
  source_table:=cfg.child_table;
  sql_where:=format('from public.%I c join public.%I p on p.id=c.%I
      where p.space_id=$1 and p.created_by=$2 and p.visibility=''private''',
      source_table,cfg.parent_table,cfg.parent_fk);
  fault_where:=format('c.%I is distinct from $2',cfg.author_col);
  if source_table in ('occasion_budget_log','occasion_plan_revisions') then
    -- Trigger-inserted audit rows without actor are legitimate.
    fault_where:=format('c.%I is not null and c.%I<>$2',
       item.author_col,item.author_col);
  end if;
  if source_table='scrapbook_pages' then
     fault_where:=fault_where||
       ' or (c.updated_by is not null and c.updated_by<>$2)';
  elsif source_table='reminder_actions' then
     fault_where:=fault_where||' or c.recipient_id<>$2';
  elsif source_table='note_references' then
     fault_where:=fault_where||
       ' or private.qa_portable_target_scope(c.target_kind,c.target_id,p.space_id,$2)=''blocked''';
  end if;
  execute 'select count(*), count(*) filter(where ('||fault_where||')),
       coalesce(jsonb_agg(private.qa_structured_value(to_jsonb(c))
           order by to_jsonb(c)::text),''[]''::jsonb) '||sql_where
  into n,bad,records using sid,me;
  if n>500 then raise exception 'Private census exceeds 500 rows in %',source_table;end if;
  if bad>0 then
    raise exception 'Unmirrored private child scope mismatch: %',source_table;
  end if;
  if octet_length(convert_to(records::text,'UTF8'))>2097152 then
    raise exception 'Private census payload exceeds 2 MiB: %',source_table;end if;
  total:=total+n;
  fingerprint:=encode(extensions.digest(
     convert_to(records::text,'UTF8'),'sha256'),'hex');
  result_rows:=result_rows||jsonb_build_array(jsonb_build_object(
     'source_table',source_table,'private_rows',n,
     'source_sha256',fingerprint));
 end loop;
 -- Archived/private Love Letters remain author-only; opened sent letters
 -- are shared and MUST NOT be counted as private copies for the recipient.
 select count(*),
   coalesce(jsonb_agg(private.qa_structured_value(to_jsonb(l))
     order by l.id),'[]'::jsonb)
 into n,records from public.couple_letters l
 where l.space_id=sid and l.author_id=me
   and (l.status<>'sent' or (l.open_on is not null and l.open_on>current_date));
 if n>500 then raise exception 'Private Love Letters exceed census limit';end if;
 total:=total+n;
 result_rows:=result_rows||jsonb_build_array(jsonb_build_object(
    'source_table','couple_letters','private_rows',n,
    'source_sha256',encode(extensions.digest(
     convert_to(records::text,'UTF8'),'sha256'),'hex')));

 -- A draft/future-open letter MUST NOT have any read receipts. A leaked
 -- read row is a privacy breach, not an exportable historical completion.
 select count(*) into bad from public.couple_letter_reads read
 join public.couple_letters letter on letter.id=read.letter_id
 where letter.space_id=sid and letter.author_id=me
   and (letter.status<>'sent' or
      (letter.open_on is not null and letter.open_on>current_date));
 if bad>0 then raise exception 'Private Love Letter has unauthorized read receipts';end if;
 result_rows:=result_rows||jsonb_build_array(jsonb_build_object(
    'source_table','couple_letter_reads','private_rows',0,
    'source_sha256',encode(extensions.digest(
     convert_to('[]','UTF8'),'sha256'),'hex')));

 -- Place visits carry their own space_id, but must still point to the
 -- original owner's private place with the same exact space.
 select count(*),
   count(*) filter(where v.created_by<>me or v.space_id<>sid),
   coalesce(jsonb_agg(private.qa_structured_value(to_jsonb(v))-'memory_id'
     order by v.id),'[]'::jsonb)
 into n,bad,records from public.place_visits v
 join public.places p on p.id=v.place_id
 where p.space_id=sid and p.created_by=me and p.visibility='private';
 if bad>0 then raise exception 'Private place visit author or space mismatch';end if;
 if n>500 then raise exception 'Private place visits exceed census limit';end if;
 total:=total+n;
 result_rows:=result_rows||jsonb_build_array(jsonb_build_object(
    'source_table','place_visits','private_rows',n,
    'source_sha256',encode(extensions.digest(
       convert_to(records::text,'UTF8'),'sha256'),'hex')));

 -- A polymorphic link with any private endpoint is a private reference.
 -- Every owner-authored link must validate both endpoints. Unknown links
 -- must block readiness rather than silently disappearing from totals.
 select count(*) into bad from public.item_links l where l.space_id=sid
  and l.created_by=me and (
     private.qa_portable_target_scope(l.from_kind,l.from_id,sid,me)='blocked'
     or private.qa_portable_target_scope(l.to_kind,l.to_id,sid,me)='blocked');
 if bad>0 then raise exception 'Polymorphic private link has missing/hidden target';end if;
 select count(*),
   coalesce(jsonb_agg(private.qa_structured_value(to_jsonb(l))
      order by l.id),'[]'::jsonb)
 into n,records from public.item_links l where l.space_id=sid
  and l.created_by=me and
  (private.qa_portable_target_scope(l.from_kind,l.from_id,sid,me)='private'
   or private.qa_portable_target_scope(l.to_kind,l.to_id,sid,me)='private');
 if n>500 then raise exception 'Private item links exceed census limit';end if;
 total:=total+n;
 result_rows:=result_rows||jsonb_build_array(jsonb_build_object(
    'source_table','item_links','private_rows',n,
    'source_sha256',encode(extensions.digest(
       convert_to(records::text,'UTF8'),'sha256'),'hex')));

 -- Audit actions resolve against their current original records and are
 -- never replayable. Include private-owned history, fail if its actor is
 -- another person, and reject orphan history authored by this owner.
 select count(*) into bad from public.record_action_history h
 where h.space_id=sid and h.actor_id=me and
  private.qa_action_history_record_scope(
    h.record_kind,h.record_id,sid,me)='blocked';
 if bad>0 then raise exception 'Private action history has orphan source';end if;
 select count(*),
    count(*) filter(where h.actor_id is not null and h.actor_id<>me),
    coalesce(jsonb_agg(private.qa_structured_value(to_jsonb(h))
       order by h.id),'[]'::jsonb)
 into n,bad,records from public.record_action_history h
 where h.space_id=sid and private.qa_action_history_record_scope(
   h.record_kind,h.record_id,sid,me)='private';
 if bad>0 then raise exception 'Private action history actor mismatch';end if;
 if n>500 then raise exception 'Private action history exceeds census limit';end if;
 total:=total+n;
 result_rows:=result_rows||jsonb_build_array(jsonb_build_object(
    'source_table','record_action_history','private_rows',n,
    'source_sha256',encode(extensions.digest(
       convert_to(records::text,'UTF8'),'sha256'),'hex')));

 -- Occasion proposal item links must resolve via the *same* original
 -- plan, not just through both existing parent rows.
 select count(*),
   count(*) filter(where proposal.created_by<>me
     or item.plan_id<>plan.id or item.created_by<>me),
   coalesce(jsonb_agg(private.qa_structured_value(to_jsonb(link))
     order by link.proposal_id,link.item_id),'[]'::jsonb)
 into n,bad,records
 from public.occasion_proposal_items link
 join public.occasion_proposals proposal on proposal.id=link.proposal_id
 join public.occasion_plans plan on plan.id=proposal.plan_id
 join public.occasion_budget_items item on item.id=link.item_id
 where plan.space_id=sid and plan.created_by=me and plan.visibility='private';
 if bad>0 then raise exception 'Private proposal link points outside owner plan';end if;
 if n>500 then raise exception 'Private proposal links exceed census limit';end if;
 total:=total+n;
 result_rows:=result_rows||jsonb_build_array(jsonb_build_object(
    'source_table','occasion_proposal_items','private_rows',n,
    'source_sha256',encode(extensions.digest(
       convert_to(records::text,'UTF8'),'sha256'),'hex')));

 if jsonb_array_length(result_rows)<>19 then
   raise exception 'Unmirrored private table enumeration incomplete';end if;
 if total>5000 then raise exception 'Private source census exceeds 5000 records';end if;
 return jsonb_build_object(
   'schema','onespace.qa.unmirrored-private-source-census.v1',
   'owner_id',me,'source_space_id',sid,
   'unmirrored_root_types',4,'unmirrored_child_types',15,
   'table_families_checked',jsonb_array_length(result_rows),
   'private_source_rows_checked',total,
   'per_table',result_rows,
   'source_of_truth_counted',true,
   'snapshots_persisted',false,'full_source_manifest_complete',false,
   'source_data_encrypted',false,'archive_issued',false,
   'can_restore',false,'safe_to_archive',false,'safe_to_separate',false,
   'warning','Current owner-private source hashes for 19 previously unmirrored types only. No original source content or portable archive is issued.');
end $fn$;
