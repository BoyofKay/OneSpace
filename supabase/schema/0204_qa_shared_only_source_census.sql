-- QA 0204: recipient-aware reference-only census for 12 shared-only
-- classified families. Shared comments archived by B stay private to B.
create or replace function private.qa_shared_only_source_census()
returns jsonb language plpgsql stable security definer set search_path='' as $fn$
declare
 me uuid:=auth.uid(); sid uuid; cfg record;
 type_name text; bad bigint; n bigint; all_count bigint:=0;
 source_rows jsonb; result_rows jsonb:='[]'::jsonb; where_sql text; faults text;
 child_types text[]:=array[
 'partner_checkin_acknowledgements','shared_experience_comments',
 'shared_experience_interests','shared_experience_reviews',
 'shared_experience_revisions'];
 root_types text[]:=array[
 'spaces','space_tags','space_special_dates','space_holiday_sources',
 'partner_gestures','partner_checkin_requests','shared_experiences'];
begin
 if me is null then raise exception 'Sign in required';end if;
 if (select count(*) from public.space_members where user_id=me)<>1
 then raise exception 'Exactly one active space required';end if;
 select space_id into sid from public.space_members where user_id=me;
 if (private.qa_archive_catalog_coverage()->>'classification_complete')<>'true'
 then raise exception 'Shared source census blocked by schema drift';end if;
 if (select count(*) from private.qa_archive_table_policy
   where approved and disposition='shared_only'
    and source_table=any(root_types))<>7
 or (select count(*) from private.qa_archive_table_policy
   where approved and disposition='shared_only'
    and source_table=any(child_types))<>5
 then raise exception 'Shared-only source family scope changed';end if;
 if not exists(select 1 from public.spaces s where s.id=sid
   and exists(select 1 from public.space_members sm
     where sm.space_id=sid and sm.user_id=s.created_by))
 then raise exception 'Shared space original creator lineage mismatch';end if;
 for cfg in select * from (values
 ('spaces','created_by'),
 ('space_tags','created_by'),
 ('space_special_dates','created_by'),
 ('space_holiday_sources','configured_by'),
 ('partner_gestures','sender_id'),
 ('partner_checkin_requests','sender_id'),
 ('shared_experiences','created_by')
 ) as source(table_name,author_column)
 loop
  type_name:=cfg.table_name;
  if type_name='spaces' then
    where_sql:=' from public.spaces r where r.id=$1';
  else
    where_sql:=format(' from public.%I r where r.space_id=$1',type_name);
  end if;
  faults:=format('r.%I is not null and not exists(
      select 1 from public.space_members x
      where x.space_id=$1 and x.user_id=r.%I)',
      cfg.author_column,cfg.author_column);
  if type_name in ('partner_gestures','partner_checkin_requests') then
     faults:=faults||' or not exists(select 1 from public.space_members x
       where x.space_id=$1 and x.user_id=r.recipient_id)
       or r.recipient_id=r.sender_id';
  end if;
  execute 'select count(*),count(*) filter(where ('||faults||')),
     coalesce(jsonb_agg(private.qa_structured_value(to_jsonb(r))'
       ||case when type_name='partner_gestures'
          then '-''gesture_schedule_id''' when type_name='space_special_dates'
          then '-''person_id''' else '' end||
     ' order by to_jsonb(r)::text),''[]''::jsonb)'||where_sql
  into n,bad,source_rows using sid;
  if bad>0 then
    raise exception 'Shared-only original partner lineage mismatch: %',type_name;
  end if;
  if n>500 or octet_length(convert_to(source_rows::text,'UTF8'))>2097152 then
    raise exception 'Shared-only source exceeds census size limits: %',type_name;
  end if;
  all_count:=all_count+n;
  result_rows:=result_rows||jsonb_build_array(jsonb_build_object(
   'source_table',type_name,'visible_shared_rows',n,
   'source_sha256',encode(extensions.digest(
     convert_to(source_rows::text,'UTF8'),'sha256'),'hex')));
 end loop;
 for cfg in select * from (values
 ('shared_experience_comments','created_by'),
 ('shared_experience_interests','user_id'),
 ('shared_experience_reviews','user_id'),
 ('shared_experience_revisions','changed_by'),
 ('partner_checkin_acknowledgements','user_id')
 ) as source(table_name,author_column)
 loop
  type_name:=cfg.table_name;
  if type_name='partner_checkin_acknowledgements' then
    where_sql:=' from public.partner_checkin_acknowledgements r
      join public.partner_checkin_requests parent on parent.id=r.request_id
      where parent.space_id=$1';
    faults:='parent.responded_at is null
      or r.user_id is distinct from parent.sender_id
      or not exists(select 1 from public.space_members x
         where x.space_id=$1 and x.user_id=parent.sender_id)
      or not exists(select 1 from public.space_members x
         where x.space_id=$1 and x.user_id=parent.recipient_id)';
  else
    where_sql:=format(' from public.%I r
       join public.shared_experiences parent on parent.id=r.experience_id
       where parent.space_id=$1',type_name);
    faults:=format('r.%I is not null and not exists(
      select 1 from public.space_members x
      where x.space_id=$1 and x.user_id=r.%I)',
      cfg.author_column,cfg.author_column);
  end if;
  -- Verify ALL source rows for invalid foreign member contributions,
  -- including comments hidden from this particular recipient.
  execute 'select count(*) filter(where ('||faults||'))'||where_sql
     into bad using sid;
  if bad>0 then
    raise exception 'Shared-only dependent privacy or response mismatch: %',type_name;
  end if;
  if type_name='shared_experience_comments' then
    where_sql:=where_sql||' and (r.archived_at is null or r.created_by=$2)';
  elsif type_name='partner_checkin_acknowledgements' then
    where_sql:=where_sql||' and parent.responded_at is not null
      and $2 in (parent.sender_id,parent.recipient_id)';
  end if;
  execute 'select count(*),
     coalesce(jsonb_agg(private.qa_structured_value(to_jsonb(r))'
       ||case when type_name='shared_experience_comments'
              then '-''reply_to''' else '' end||
       ' order by to_jsonb(r)::text),''[]''::jsonb)'||where_sql
     into n,source_rows using sid,me;
  if n>500 or octet_length(convert_to(source_rows::text,'UTF8'))>2097152 then
    raise exception 'Shared dependent over size cap: %',type_name;
  end if;
  all_count:=all_count+n;
  result_rows:=result_rows||jsonb_build_array(jsonb_build_object(
   'source_table',type_name,'visible_shared_rows',n,
   'source_sha256',encode(extensions.digest(
      convert_to(source_rows::text,'UTF8'),'sha256'),'hex')));
 end loop;
 if jsonb_array_length(result_rows)<>12 then
   raise exception 'Shared-only table census list is incomplete';end if;
 return jsonb_build_object(
  'schema','onespace.qa.shared-only-source-census.v1',
  'owner_id',me,'source_space_id',sid,
  'shared_only_table_types_checked',12,
  'recipient_visible_shared_rows',all_count,
  'per_table',result_rows,
  'archived_partner_comments_excluded',true,
  'shared_eligible_mixed_visibility_rows_complete',false,
  'shared_source_snapshots_persisted',false,
  'encrypted_archive_issued',false,
  'can_restore',false,'safe_to_archive',false,'safe_to_separate',false,
  'warning','Source census only. Historical archived partner comments are author-only. Shared records in mixed-visibility tables still need separate completeness verification.'
 );
end $fn$;
revoke all on function private.qa_shared_only_source_census()
 from public,anon,authenticated;
grant execute on function private.qa_shared_only_source_census()
 to authenticated;
create or replace function public.qa_shared_only_source_census()
returns jsonb language sql stable security invoker set search_path='' as $fn$
 select private.qa_shared_only_source_census()
$fn$;
revoke all on function public.qa_shared_only_source_census()
 from public,anon;
grant execute on function public.qa_shared_only_source_census()
 to authenticated;
