-- QA 0202: four owner-private root families missing from the 14+9
-- mirrored Personal Vault and 19 unmirrored private/shared source census.
create or replace function private.qa_owner_private_source_census()
returns jsonb language plpgsql stable security definer set search_path='' as $fn$
declare
 me uuid:=auth.uid(); sid uuid; x record;
 rows jsonb; n bigint; total bigint:=0; sizes integer;
 outrows jsonb:='[]'::jsonb;
begin
 if me is null then raise exception 'Sign in required';end if;
 if (select count(*) from public.space_members sm where sm.user_id=me)<>1
 then raise exception 'Exactly one current relationship required';end if;
 select space_id into sid from public.space_members where user_id=me;
 if (private.qa_archive_catalog_coverage()->>'classification_complete')<>'true'
 then raise exception 'Archive schema drift needs review';end if;
 if (select count(*) from private.qa_archive_table_policy
 where relation_kind='root' and approved
   and disposition='owner_private' and source_table in (
    'gesture_message_overrides','gesture_schedules',
    'gesture_templates','personal_days_off'))<>4
 then raise exception 'Owner-private source scope changed';end if;
 for x in select * from (values
   ('gesture_message_overrides','owner_id'),
   ('gesture_schedules','sender_id'),
   ('gesture_templates','creator_id'),
   ('personal_days_off','user_id')
 ) as families(table_name,owner_column)
 loop
   execute format(
    'select count(*),
      coalesce(jsonb_agg(private.qa_structured_value(to_jsonb(t))
      order by t.id),''[]''::jsonb)
     from public.%I t where t.space_id=$1 and t.%I=$2',
    x.table_name,x.owner_column)
    into n,rows using sid,me;
   if n>500 then raise exception 'Private owner-only source over cap: %',x.table_name;end if;
   sizes:=octet_length(convert_to(rows::text,'UTF8'));
   if sizes>2097152 then raise exception 'Owner-only source data over 2 MiB: %',x.table_name;end if;
   total:=total+n;
   outrows:=outrows||jsonb_build_array(jsonb_build_object(
    'source_table',x.table_name,'private_rows',n,
    'source_sha256',encode(extensions.digest(
       convert_to(rows::text,'UTF8'),'sha256'),'hex')));
 end loop;
 return jsonb_build_object(
  'schema','onespace.qa.owner-only-source-census.v1',
  'owner_id',me,'source_space_id',sid,
  'owner_private_families_checked',4,
  'private_source_rows_checked',total,
  'per_table',outrows,
  'source_of_truth_counted',true,
  'snapshots_persisted',false,
  'encrypted_portable_archive_complete',false,
  'can_restore',false,'safe_to_archive',false,'safe_to_separate',false);
end $fn$;
revoke all on function private.qa_owner_private_source_census()
 from public,anon,authenticated;
grant execute on function private.qa_owner_private_source_census()
 to authenticated;

create or replace function public.qa_owner_private_source_census()
returns jsonb language sql stable security invoker set search_path='' as $fn$
 select private.qa_owner_private_source_census()
$fn$;
revoke all on function public.qa_owner_private_source_census()
 from public,anon;
grant execute on function public.qa_owner_private_source_census()
 to authenticated;
