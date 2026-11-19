-- QA 0203: one owner/space-bound census for all 46 private-eligible
-- table families (42 private/shared + 4 owner-only). No portable payload.
create or replace function private.qa_private_source_inventory()
returns jsonb language plpgsql stable security definer set search_path='' as $fn$
declare
 me uuid:=auth.uid();
 sid uuid;
 mirror jsonb;
 unmirrored jsonb;
 owner_only jsonb;
 registry_count int;
 family_count int:=46;
 total_count bigint;
 digest_value text;
begin
 if me is null then raise exception 'Sign in required';end if;
 if (select count(*) from public.space_members where user_id=me)<>1
 then raise exception 'Exactly one current original space is required';end if;
 select space_id into sid from public.space_members where user_id=me;
 if (select count(*) from private.qa_archive_table_policy
    where approved and disposition in ('private_shared','owner_private'))<>46
 then raise exception 'Private source family inventory policy changed';end if;
 if (private.qa_archive_catalog_coverage()->>'classification_complete')<>'true'
 then raise exception 'Unclassified schema drift prevents a private source inventory';end if;
 mirror:=private.qa_private_vault_subset_fingerprint();
 unmirrored:=private.qa_unmirrored_private_source_census();
 owner_only:=private.qa_owner_private_source_census();

 if mirror->>'owner_id'<>me::text or unmirrored->>'owner_id'<>me::text
    or owner_only->>'owner_id'<>me::text
    or mirror->>'source_space_id'<>sid::text
    or unmirrored->>'source_space_id'<>sid::text
    or owner_only->>'source_space_id'<>sid::text
 then raise exception 'Mismatched private-source census owner or space';end if;
 if (mirror->>'mirrored_root_types')::int<>14
  or (mirror->>'mirrored_child_types')::int<>9
  or (unmirrored->>'table_families_checked')::int<>19
  or (owner_only->>'owner_private_families_checked')::int<>4
  or jsonb_array_length(unmirrored->'per_table')<>19
  or jsonb_array_length(owner_only->'per_table')<>4
 then raise exception 'Incomplete private-source table coverage';end if;
 if mirror->>'root_mirror_verified'<>'true'
  or mirror->>'supported_child_mirrors_verified'<>'true'
 then raise exception 'Private mirror records were not independently verified';end if;
 total_count:=(mirror->>'snapshot_record_count')::bigint
  +(unmirrored->>'private_source_rows_checked')::bigint
  +(owner_only->>'private_source_rows_checked')::bigint;
 if total_count>10000 then raise exception 'Private source census over cap';end if;
 digest_value:=encode(extensions.digest(convert_to(
   'onespace.qa.private-source-inventory.v1|'||me::text||'|'||sid::text||
   '|mirrored='||(mirror->>'subset_sha256')||
   '|remaining='||coalesce((unmirrored->'per_table')::text,'')||
   '|owner_only='||coalesce((owner_only->'per_table')::text,''),
    'UTF8'),'sha256'),'hex');
 return jsonb_build_object(
   'schema','onespace.qa.private-source-inventory.v1',
   'owner_id',me,'source_space_id',sid,
   'privacy_classified_table_types',69,
   'private_eligible_table_types',family_count,
   'mirrored_root_types_verified',14,
   'mirrored_child_types_verified',9,
   'unmirrored_private_shared_types_counted',19,
   'owner_private_types_counted',4,
   'private_source_rows_counted',total_count,
   'source_inventory_sha256',digest_value,
   'mirrored_subset_sha256',mirror->'subset_sha256',
   'unmirrored_per_table',unmirrored->'per_table',
   'owner_only_per_table',owner_only->'per_table',
   'all_private_eligible_types_censused',true,
   'all_private_content_persistently_snapshotted',false,
   'shared_relationship_content_censused',false,
   'complete_archive_manifest_created',false,
   'server_authenticated_archive_issued',false,
   'is_verified_archive',false,'ready_to_restore',false,
   'can_restore',false,'safe_to_archive',false,'safe_to_separate',false,
   'warning','Privacy scope and per-table private-source counts/hashes are checked, but 23 source families outside the verified mirror are NOT yet durably packaged and shared relationship content is not covered.'
 );
end $fn$;
revoke all on function private.qa_private_source_inventory()
 from public,anon,authenticated;
grant execute on function private.qa_private_source_inventory()
 to authenticated;
create or replace function public.qa_private_source_inventory()
returns jsonb language sql stable security invoker set search_path='' as $fn$
 select private.qa_private_source_inventory()
$fn$;
revoke all on function public.qa_private_source_inventory()
 from public,anon;
grant execute on function public.qa_private_source_inventory()
 to authenticated;
