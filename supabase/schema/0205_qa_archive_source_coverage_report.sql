-- QA 0205: unify all 69 classified *table family* categories into
-- a truthful per-recipient source coverage report. Not a portable archive.
create or replace function private.qa_archive_source_coverage_report()
returns jsonb language plpgsql stable security definer set search_path='' as $fn$
declare
 me uuid:=auth.uid(); sid uuid;
 owner_private jsonb; shared_only jsonb;
 excluded_media int; excluded_operational int; classified int;
 digest_value text;
begin
 if me is null then raise exception 'Sign in required';end if;
 if (select count(*) from public.space_members where user_id=me)<>1
 then raise exception 'Exactly one active relationship required';end if;
 select space_id into sid from public.space_members where user_id=me;
 select count(*) into classified from private.qa_archive_table_policy where approved;
 select count(*) into excluded_media
 from private.qa_archive_table_policy where approved and disposition='media_excluded';
 select count(*) into excluded_operational
 from private.qa_archive_table_policy where approved and disposition='system_excluded';
 if classified<>69 or excluded_media<>4 or excluded_operational<>7
 or (private.qa_archive_catalog_coverage()->>'classification_complete')<>'true'
 then raise exception 'Archive classification schema is out of date';end if;

 owner_private:=private.qa_private_source_inventory();
 shared_only:=private.qa_shared_only_source_census();
 if owner_private->>'owner_id'<>me::text
 or shared_only->>'owner_id'<>me::text
 or owner_private->>'source_space_id'<>sid::text
 or shared_only->>'source_space_id'<>sid::text
 or (owner_private->>'private_eligible_table_types')::int<>46
 or (shared_only->>'shared_only_table_types_checked')::int<>12
 then raise exception 'Archive family source attribution mismatch';end if;
 if owner_private->>'all_private_eligible_types_censused'<>'true'
 or shared_only->>'archived_partner_comments_excluded'<>'true'
 then raise exception 'Private/shared source coverage incomplete';end if;
 digest_value:=encode(extensions.digest(convert_to(
   'onespace.qa.source-coverage-report.v1|'||me::text||'|'||sid::text||
    '|private='||(owner_private->>'source_inventory_sha256')||
    '|shared-only='||(shared_only->'per_table')::text||
    '|excluded-media=4|excluded-operational=7',
    'UTF8'),'sha256'),'hex');

 return jsonb_build_object(
  'schema','onespace.qa.source-coverage-report.v1',
  'recipient_id',me,'source_space_id',sid,
  'classified_table_types',69,
  'private_eligible_table_types_censused',46,
  'shared_only_table_types_censused',12,
  'media_excluded_table_types',4,
  'operational_excluded_table_types',7,
  'table_types_accounted_for',69,
  'private_source_rows_counted',owner_private->'private_source_rows_counted',
  'recipient_visible_shared_only_rows_counted',shared_only->'recipient_visible_shared_rows',
  'source_coverage_sha256',digest_value,
  'private_inventory_sha256',owner_private->'source_inventory_sha256',
  'shared_only_per_table',shared_only->'per_table',
  'mixed_visibility_shared_rows_censused',false,
  'full_per_row_source_manifest_complete',false,
  'all_written_records_durably_packaged',false,
  'trusted_server_signature_present',false,
  'independently_verified_encrypted_archive',false,
  'restoration_tested',false,
  'safe_to_archive',false,'safe_to_separate',false,'can_restore',false,
  'warning','69 known table policies accounted for, but not all source rows: shared records in mixed-visibility tables still need enumeration. No durable 69-type encrypted backup or trusted restoration exists.'
 );
end $fn$;
revoke all on function private.qa_archive_source_coverage_report()
 from public,anon,authenticated;
grant execute on function private.qa_archive_source_coverage_report()
 to authenticated;
create or replace function public.qa_archive_source_coverage_report()
returns jsonb language sql stable security invoker set search_path='' as $fn$
 select private.qa_archive_source_coverage_report()
$fn$;
revoke all on function public.qa_archive_source_coverage_report()
 from public,anon;
grant execute on function public.qa_archive_source_coverage_report()
 to authenticated;
