-- QA 0183: activity component, comment, reaction, decision and revision
-- coverage, with strict per-recipient parent/author privacy checks.
-- Preview only: never a restored or verified encrypted archive.
do $guard$
begin
 if (select count(*) from private.qa_archive_table_policy
   where source_table in ('activity_comments','activity_component_reactions',
       'activity_component_revisions','activity_components',
       'activity_decisions','activity_revisions')
     and relation_kind='dependent' and canonical_parent='activities'
     and disposition='review_required' and not approved)<>6 then
   raise exception 'Activity descendant classification requires review';end if;
end $guard$;
update private.qa_archive_table_policy
set disposition='private_shared',approved=true,reviewed_at=now(),
  policy_note='Activity child inherits the parent privacy. For private parents, all child contributions must be authored solely by root owner; for shared parents, all authors belong to original pair. Null system actors are blocked for private parents. Embedded media payload/voice paths excluded. Structured preview only; restore mapping and portable encryption unimplemented.'
where source_table in ('activity_comments','activity_component_reactions',
  'activity_component_revisions','activity_components',
  'activity_decisions','activity_revisions')
 and relation_kind='dependent' and canonical_parent='activities'
 and disposition='review_required' and not approved;

create or replace function private.qa_activity_nested_structured_preview(p_activity_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $fn$
declare
 caller uuid:=auth.uid();
 root public.activities%rowtype;
 t text;
 actor_col text;
 ordering text;
 child_rows jsonb;
 children jsonb:='{}'::jsonb;
 total_rows int:=0;
 bad int;
 n int;
 all_tables text[]:=array[
   'activity_components','activity_comments',
   'activity_component_reactions','activity_decisions',
   'activity_component_revisions','activity_revisions'];
 payload jsonb;
begin
 if caller is null then raise exception 'Sign in required';end if;
 select a.* into root from public.activities a
 join public.space_members m on m.space_id=a.space_id and m.user_id=caller
 where a.id=p_activity_id and
      (a.visibility='shared' or a.created_by=caller);
 if not found then raise exception 'Activity preview not found';end if;
 if (select count(*) from public.space_members where user_id=caller)<>1
 then raise exception 'Activity preview not found';end if;
 if root.visibility not in ('private','shared')
 then raise exception 'Unsupported activity visibility';end if;
 if not exists(select 1 from public.space_members m
       where m.space_id=root.space_id and m.user_id=root.created_by)
 then raise exception 'Activity owner lineage mismatch';end if;
 if (select count(*) from private.qa_archive_table_policy
     where source_table=any(array['activities']||all_tables)
       and approved and disposition='private_shared')<>7
 then raise exception 'Activity structured archive scope incomplete';end if;
 foreach t in array all_tables loop
   actor_col:=case t
     when 'activity_components' then 'created_by'
     when 'activity_comments' then 'author_id'
     when 'activity_component_reactions' then 'user_id'
     when 'activity_decisions' then 'created_by'
     else 'changed_by' end;
   -- Snapshot fields including image/voice IDs and Storage paths are
   -- recursively sanitized. A contributor from a former relationship
   -- cannot be imported into an owner-private item or old shared archive.
   execute format(
    'select count(*) from public.%I c
      where c.activity_id=$1 and
       (case when $2=''private''
          then c.%I is distinct from $3
          else c.%I is not null and not exists (
            select 1 from public.space_members m
            where m.space_id=$4 and m.user_id=c.%I)
        end)',t,actor_col,actor_col,actor_col)
    into bad using root.id,root.visibility,root.created_by,root.space_id;
   if bad<>0 then
     raise exception 'Activity child contributor lineage mismatch: %',t;end if;
   execute format('select count(*) from public.%I c
       where c.activity_id=$1',t)
     into n using root.id;
   total_rows:=total_rows+n;
   if total_rows>500 then
      raise exception 'Activity structured package exceeds 500 children';end if;
   ordering:=case t
       when 'activity_component_reactions'
         then 'c.component_id,c.user_id'
       when 'activity_revisions' then 'c.changed_at,c.id'
       when 'activity_component_revisions' then 'c.changed_at,c.id'
       else 'c.created_at,c.id' end;
   if t='activity_component_reactions' then
     execute format(
       'select coalesce(jsonb_agg(private.qa_structured_value(to_jsonb(c))
         order by %s),''[]''::jsonb)
          from public.%I c where c.activity_id=$1',ordering,t)
       into child_rows using root.id;
   else
     execute format(
       'select coalesce(jsonb_agg(jsonb_build_object(
         ''source_id'',c.id,
         ''structured'',private.qa_structured_value(to_jsonb(c)))
         order by %s),''[]''::jsonb)
          from public.%I c where c.activity_id=$1',ordering,t)
       into child_rows using root.id;
   end if;
   children:=children||jsonb_build_object(t,child_rows);
 end loop;
 payload:=jsonb_build_object(
   'schema','onespace.activity-structured-preview.v1',
   'kind',case when root.visibility='private'
      then 'private_owner_only' else 'shared_reference_only' end,
   'recipient_id',caller,'owner_id',root.created_by,
   'source_space_id',root.space_id,
   'root',jsonb_build_object('table','activities','source_id',root.id,
       'structured',private.qa_structured_value(to_jsonb(root))),
   'children',children,'child_record_count',total_rows
 );
 if octet_length(convert_to(payload::text,'UTF8'))>2097152 then
   raise exception 'Activity structured package exceeds 2 MiB';end if;
 return jsonb_build_object('payload',payload,
   'payload_sha256',encode(extensions.digest(
     convert_to(payload::text,'UTF8'),'sha256'),'hex'),
   'media_included',false,'documents_included',false,
   'encrypted',false,'is_verified_archive',false,
   'can_restore',false,'safe_to_separate',false,
   'warning','Written activity preview only: attachment bytes, media and paths excluded. Shared history cannot be restored.');
end $fn$;
revoke all on function private.qa_activity_nested_structured_preview(uuid)
 from public,anon,authenticated;
grant execute on function private.qa_activity_nested_structured_preview(uuid)
 to authenticated;
