-- QA 0190: polymorphic item/note references must validate BOTH ends
-- against the same original space; no reference may leak partner-private IDs.
create or replace function private.qa_portable_target_scope(
 p_kind text,p_id uuid,p_space uuid,p_recipient uuid
) returns text language plpgsql stable security definer set search_path='' as $fn$
declare tab text; v record;
begin
 if auth.uid() is null or auth.uid()<>p_recipient then
 return 'blocked';end if;
 if not exists(select 1 from public.space_members sm
  where sm.space_id=p_space and sm.user_id=p_recipient) then
 return 'blocked';end if;
 if p_kind='experience' then
   if exists(select 1 from public.shared_experiences x
     where x.id=p_id and x.space_id=p_space) then return 'shared';end if;
   return 'blocked';
 end if;
 tab:=case p_kind
 when 'activity' then 'activities' when 'trip' then 'shared_trips'
 when 'occasion' then 'occasion_plans' when 'event' then 'space_events'
 when 'reminder' then 'reminders' when 'task' then 'tasks'
 when 'note' then 'notes' when 'memory' then 'memories'
 else null end;
 if tab is null then return 'blocked';end if;
 execute format('select t.visibility,t.created_by from public.%I t
 where t.id=$1 and t.space_id=$2',tab)
 into v using p_id,p_space;
 if not found then return 'blocked';end if;
 if v.visibility='shared' then return 'shared';end if;
 if v.visibility='private' and v.created_by=p_recipient
 then return 'private';end if;
 return 'blocked';
end $fn$;
revoke all on function private.qa_portable_target_scope(text,uuid,uuid,uuid)
 from public,anon,authenticated;

do $guard$
begin
 if (select count(*) from private.qa_archive_table_policy
 where source_table in ('note_references','item_links')
  and not approved and disposition='review_required')<>2 then
 raise exception 'Polymorphic association table requires fresh review';end if;
end $guard$;
update private.qa_archive_table_policy set
 disposition='private_shared',approved=true,reviewed_at=now(),
 policy_note=case source_table
 when 'note_references' then
 'Reference must remain in same original space and be visible to the recipient. A shared note never exports references to private targets; a private note exports owner-only links. All target pointers are navigation-only and cannot be reattached without trusted restore ID mapping.'
 else
 'Both polymorphic link endpoints must exist in same original space. An endpoint owner-private is visible only to its owner and cannot be exported as the other member; the link creator must own private endpoints. Old links never become live connections to a new relationship.'
 end
where source_table in ('note_references','item_links') and disposition='review_required' and not approved;

create or replace function private.qa_note_reference_history_preview(p_note_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $fn$
declare me uuid:=auth.uid(); root public.notes%rowtype; invalid int; n int;
 rows jsonb; package jsonb;
begin
 if me is null then raise exception 'Sign in required';end if;
 if (select count(*) from public.space_members where user_id=me)<>1
 then raise exception 'Note not found';end if;
 select x.* into root from public.notes x
 join public.space_members sm on sm.space_id=x.space_id and sm.user_id=me
 where x.id=p_note_id and (x.visibility='shared' or x.created_by=me);
 if not found then raise exception 'Note not found';end if;
 if root.visibility not in ('shared','private') then
 raise exception 'Invalid note visibility';end if;
 if (select count(*) from private.qa_archive_table_policy where approved and disposition='private_shared'
 and source_table in ('notes','note_references'))<>2
 then raise exception 'Note associations not approved';end if;
 select count(*) into invalid from public.note_references x
 where x.note_id=root.id and (
   (root.visibility='private' and x.created_by<>root.created_by)
   or (root.visibility='shared' and not exists(select 1 from public.space_members sm
      where sm.space_id=root.space_id and sm.user_id=x.created_by))
   or private.qa_portable_target_scope(x.target_kind,x.target_id,root.space_id,me)='blocked'
   or (root.visibility='shared' and
      private.qa_portable_target_scope(x.target_kind,x.target_id,root.space_id,me)<>'shared')
 );
 if invalid>0 then raise exception 'Note target visibility, author or space mismatch';end if;
 select count(*) into n from public.note_references x where x.note_id=root.id;
 if n>500 then raise exception 'Note references exceed 500 links';end if;
 select coalesce(jsonb_agg(private.qa_structured_value(to_jsonb(x))
  order by x.created_at,x.id),'[]'::jsonb)
 into rows from public.note_references x where x.note_id=root.id;
 package:=jsonb_build_object('schema','onespace.note-reference-preview.v1',
 'kind',case when root.visibility='private' then 'private_owner_only' else 'shared_reference_only' end,
 'owner_id',root.created_by,'recipient_id',me,'source_space_id',root.space_id,
 'root',jsonb_build_object('table','notes','source_id',root.id,
 'structured',private.qa_structured_value(to_jsonb(root))),
 'links',rows,'link_count',n);
 if octet_length(convert_to(package::text,'UTF8'))>2097152
 then raise exception 'Note reference preview exceeds 2 MiB';end if;
 return jsonb_build_object('payload',package,
 'payload_sha256',encode(extensions.digest(convert_to(package::text,'UTF8'),'sha256'),'hex'),
 'media_included',false,'documents_included',false,'encrypted',false,
 'is_verified_archive',false,'can_restore',false,'safe_to_separate',false,
 'warning','Link IDs are historical references only and must be revalidated/remapped for any private restore.');
end $fn$;
revoke all on function private.qa_note_reference_history_preview(uuid) from public,anon,authenticated;
grant execute on function private.qa_note_reference_history_preview(uuid) to authenticated;

create or replace function private.qa_item_link_history_preview(p_link_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $fn$
declare me uuid:=auth.uid(); link_row public.item_links%rowtype;
 left_scope text;right_scope text;package jsonb;
begin
 if me is null then raise exception 'Sign in required';end if;
 if (select count(*) from public.space_members sm where sm.user_id=me)<>1
 then raise exception 'Link not found';end if;
 select x.* into link_row from public.item_links x
 join public.space_members sm on sm.space_id=x.space_id and sm.user_id=me
 where x.id=p_link_id;
 if not found then raise exception 'Link not found';end if;
 if (select count(*) from private.qa_archive_table_policy
 where source_table='item_links' and approved and disposition='private_shared')<>1
 then raise exception 'Link scope not approved';end if;
 if not exists(select 1 from public.space_members sm
 where sm.space_id=link_row.space_id and sm.user_id=link_row.created_by)
 then raise exception 'Link author lineage mismatch';end if;
 left_scope:=private.qa_portable_target_scope(
    link_row.from_kind,link_row.from_id,link_row.space_id,me);
 right_scope:=private.qa_portable_target_scope(
    link_row.to_kind,link_row.to_id,link_row.space_id,me);
 if left_scope='blocked' or right_scope='blocked' then
 raise exception 'Link not found';end if;
 -- A link involving private records is owner-private even if the other
 -- endpoint is shared. The link creator must be the recipient/owner.
 if (left_scope='private' or right_scope='private')
     and link_row.created_by<>me then
 raise exception 'Link private endpoint author mismatch';end if;
 package:=jsonb_build_object('schema','onespace.item-link-reference-preview.v1',
 'kind',case when left_scope='shared' and right_scope='shared'
      then 'shared_reference_only' else 'private_owner_only' end,
 'owner_id',link_row.created_by,'recipient_id',me,
 'source_space_id',link_row.space_id,
 'link',private.qa_structured_value(to_jsonb(link_row)));
 return jsonb_build_object('payload',package,
 'payload_sha256',encode(extensions.digest(convert_to(package::text,'UTF8'),'sha256'),'hex'),
 'media_included',false,'documents_included',false,'encrypted',false,
 'is_verified_archive',false,'can_restore',false,'safe_to_separate',false,
 'warning','Link is history only; old source IDs are not actionable in another relationship.');
end $fn$;
revoke all on function private.qa_item_link_history_preview(uuid) from public,anon,authenticated;
grant execute on function private.qa_item_link_history_preview(uuid) to authenticated;
