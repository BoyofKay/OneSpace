-- QA 0193: milestone truthfulness. All 69 classifications are now
-- approved, but this MUST NOT enable archive, restore or destructive gates.
CREATE OR REPLACE FUNCTION private.qa_archive_catalog_coverage()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  me uuid:=auth.uid();
  sid uuid;
  n_unregistered_roots int;
  n_unregistered_dependents int;
  n_roots_pending int;
  n_children_pending int;
  n_approved int;
  n_excluded_media int;
  related jsonb;
begin
  if me is null then raise exception 'Sign in required'; end if;
  if (select count(*) from public.space_members where user_id=me)<>1 then
    return jsonb_build_object('has_space',false,
      'classification_complete',false,'safe_to_archive',false);
  end if;
  select space_id into sid from public.space_members where user_id=me;

  select count(*) into n_unregistered_roots
  from (select distinct c.table_name from information_schema.columns c
        where c.table_schema='public' and c.column_name='space_id'
        union select 'spaces') r
  where not exists(select 1 from private.qa_archive_table_policy p
    where p.source_table=r.table_name and p.relation_kind='root');

  related:=private.space_archive_dependency_inventory();
  select count(*) into n_unregistered_dependents
  from jsonb_array_elements(coalesce(related->'details','[]'::jsonb)) elem
  where not exists(select 1 from private.qa_archive_table_policy p
    where p.source_table=elem->>'table' and p.relation_kind='dependent');

  select count(*) into n_roots_pending from private.qa_archive_table_policy
    where relation_kind='root' and not approved;
  select count(*) into n_children_pending from private.qa_archive_table_policy
    where relation_kind='dependent' and not approved;
  select count(*) into n_approved from private.qa_archive_table_policy where approved;
  select count(*) into n_excluded_media from private.qa_archive_table_policy
    where disposition='media_excluded' and approved;

  return jsonb_build_object('has_space',true,
    'catalog_version',1,'total_tables',(select count(*) from private.qa_archive_table_policy),
    'approved_table_policies',n_approved,'root_types_pending',n_roots_pending,
    'dependent_types_pending',n_children_pending,
    'unregistered_root_types',n_unregistered_roots,
    'unregistered_dependent_types',n_unregistered_dependents,
    'media_types_excluded',n_excluded_media,
    'classification_complete',n_roots_pending=0 and n_children_pending=0
      and n_unregistered_roots=0 and n_unregistered_dependents=0,
    'safe_to_archive',false,'safe_to_separate',false,
    'encrypted_portable_archive_complete',false,
    'trusted_private_restore_complete',false,
    'source_of_truth_cutover_complete',false,
    'reason',case when n_roots_pending=0 and n_children_pending=0
      and n_unregistered_roots=0 and n_unregistered_dependents=0
    then 'Table classification is complete. Full encrypted archive generation, verified restoration, relationship-boundary migration and end-to-end acceptance remain incomplete. Leave/remove/delete remain disabled.'
    else 'Incomplete ownership classification or newly detected schema relationships block archival and relationship separation.' end);
end $function$
;