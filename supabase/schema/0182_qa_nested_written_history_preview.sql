-- QA 0182: explicitly classify three written parent-scoped child types.
-- A single per-recipient preview checks owner lineage, but does NOT create
-- portable archive files or permit restoration/separation.
do $guard$
begin
 if (select count(*) from private.qa_archive_table_policy
     where source_table in ('scrapbook_pages','trip_revisions','saved_contact_revisions')
     and relation_kind='dependent' and disposition='review_required' and not approved)<>3
 then raise exception 'Nested written-history privacy scope needs fresh review'; end if;
end $guard$;
update private.qa_archive_table_policy p
set disposition='private_shared',approved=true,reviewed_at=now(),
policy_note=case p.source_table
 when 'scrapbook_pages' then
  'Inherit memory visibility, owner-check page creator/last editor for private parents; no photos, photo IDs or media bytes. Shared contributions only from current original couple; release is a preview, not a restore.'
 when 'trip_revisions' then
  'Inherit trip visibility; private revisions require parent owner actor; shared historical changed_by must belong to original pair, NULL system actor allowed only for shared. Nested before/after sanitized to exclude media.'
 when 'saved_contact_revisions' then
  'Inherit contact visibility; only original owner private revisions, shared pair authors verified, no file/media. Revision JSON before/after is sanitized. Never restore old shared history into new space.'
end
where p.source_table in ('scrapbook_pages','trip_revisions','saved_contact_revisions')
 and p.relation_kind='dependent'
 and p.disposition='review_required' and not p.approved;

create or replace function private.qa_nested_written_history_preview(
 p_parent_table text,p_parent_id uuid
) returns jsonb language plpgsql stable security definer set search_path='' as $fn$
declare
 caller uuid:=auth.uid();
 source_parent text;
 source_child text;
 parent_row jsonb;
 parent_owner uuid;
 parent_space uuid;
 parent_visibility text;
 child_fk text;
 actor_col text;
 invalid_rows int;
 row_count int;
 payload_children jsonb;
 payload jsonb;
begin
 if caller is null then raise exception 'Sign in required';end if;
 if p_parent_table='memories' then
    source_parent:='memories';source_child:='scrapbook_pages';
    child_fk:='memory_id';actor_col:='created_by';
 elsif p_parent_table='shared_trips' then
    source_parent:='shared_trips';source_child:='trip_revisions';
    child_fk:='trip_id';actor_col:='changed_by';
 elsif p_parent_table='saved_contacts' then
    source_parent:='saved_contacts';source_child:='saved_contact_revisions';
    child_fk:='contact_id';actor_col:='changed_by';
 else
   raise exception 'Unsupported written-history root';
 end if;
 if (select count(*) from private.qa_archive_table_policy
     where approved and disposition='private_shared'
       and source_table in (source_parent,source_child))<>2
 then raise exception 'Written-history archive scope not approved';end if;
 if (select count(*) from public.space_members sm where sm.user_id=caller)<>1
 then raise exception 'Written-history root not found';end if;
 execute format(
   'select to_jsonb(p) from public.%I p
     join public.space_members sm on sm.space_id=p.space_id
        and sm.user_id=$2
     where p.id=$1 and (p.visibility=''shared'' or p.created_by=$2)',
     source_parent)
 into parent_row using p_parent_id,caller;
 if parent_row is null then raise exception 'Written-history root not found'; end if;
 parent_owner:=(parent_row->>'created_by')::uuid;
 parent_space:=(parent_row->>'space_id')::uuid;
 parent_visibility:=parent_row->>'visibility';
 if parent_visibility not in ('shared','private') then
   raise exception 'Unsupported written-history visibility';
 end if;
 if parent_visibility='shared' and not exists(
    select 1 from public.space_members sm
    where sm.space_id=parent_space and sm.user_id=parent_owner)
 then raise exception 'Written-history root owner lineage mismatch';end if;
 -- Reject non-owner private contributions, and unknown/shared outsider
 -- contributions. Audit entries with NULL actor are accepted for shared
 -- parents as system-generated; for private parents we fail closed.
 execute format(
   'select count(*) from public.%I ch
      where ch.%I=$1 and (
       ( $2 = ''private'' and
           (ch.%I is distinct from $3
            %s))
       or ( $2 = ''shared'' and
          (ch.%I is not null and not exists (
            select 1 from public.space_members sm
             where sm.space_id=$4 and sm.user_id=ch.%I)))
      )',
    source_child,child_fk,actor_col,
    case when source_child='scrapbook_pages'
       then 'or (ch.updated_by is not null and ch.updated_by <> $3)'
       else '' end,
    actor_col,actor_col)
 into invalid_rows using p_parent_id,parent_visibility,parent_owner,parent_space;
 if invalid_rows<>0 then
   raise exception 'Written-history contributor lineage mismatch';end if;
 -- Shared scrapbook pages must have both the creator and any editor in
 -- this same original relationship. No prior partner may be transported.
 if source_child='scrapbook_pages' and parent_visibility='shared' then
   select count(*) into invalid_rows from public.scrapbook_pages page
   where page.memory_id=p_parent_id and page.updated_by is not null
     and not exists(select 1 from public.space_members sm
        where sm.space_id=parent_space and sm.user_id=page.updated_by);
   if invalid_rows<>0 then
      raise exception 'Written-history editor lineage mismatch';end if;
 end if;
 execute format('select count(*) from public.%I where %I=$1',
    source_child,child_fk) into row_count using p_parent_id;
 if row_count>500 then raise exception 'Written-history preview exceeds 500 records';end if;
 execute format(
   'select coalesce(jsonb_agg(
      jsonb_build_object(''source_id'',ch.id,
        ''structured'',private.qa_structured_value(to_jsonb(ch)))
       order by %s,ch.id),''[]''::jsonb)
     from public.%I ch where ch.%I=$1',
     case when source_child='scrapbook_pages' then 'ch.page_order'
          else 'ch.changed_at' end,source_child,child_fk)
   into payload_children using p_parent_id;
 payload:=jsonb_build_object(
   'schema','onespace.nested-written-history-preview.v1',
   'kind',case when parent_visibility='private'
        then 'private_owner_only' else 'shared_reference_only' end,
   'owner_id',parent_owner,'recipient_id',caller,
   'source_space_id',parent_space,
   'root',jsonb_build_object('table',source_parent,'source_id',p_parent_id,
     'structured',private.qa_structured_value(parent_row)),
   'child_table',source_child,'children',payload_children,
   'child_record_count',row_count
 );
 if octet_length(convert_to(payload::text,'UTF8'))>2097152 then
   raise exception 'Written-history preview exceeds 2 MiB';end if;
 return jsonb_build_object(
   'payload',payload,
   'payload_sha256',encode(extensions.digest(
      convert_to(payload::text,'UTF8'),'sha256'),'hex'),
   'media_included',false,'documents_included',false,
   'encrypted',false,'is_verified_archive',false,
   'can_restore',false,'safe_to_separate',false,
   'warning','Nested written-history preview only. No uploaded media and no shared-history restoration.');
end $fn$;
revoke all on function private.qa_nested_written_history_preview(text,uuid)
 from public,anon,authenticated;
grant execute on function private.qa_nested_written_history_preview(text,uuid)
 to authenticated;
