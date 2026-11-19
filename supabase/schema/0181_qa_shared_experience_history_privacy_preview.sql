-- QA 0181: classify nested SHARED-experience history and render a
-- recipient-filtered, media-free, reference-only preview. Not a restore API.
do $guard$
begin
 if (select count(*) from private.qa_archive_table_policy
      where source_table in ('shared_experience_comments',
                             'shared_experience_revisions')
        and relation_kind='dependent'
        and canonical_parent='shared_experiences'
        and disposition='review_required'
        and not approved)<>2 then
   raise exception 'Shared-experience child privacy policy requires review';
 end if;
end $guard$;
update private.qa_archive_table_policy
 set disposition='shared_only',approved=true,reviewed_at=now(),
 policy_note=case source_table
   when 'shared_experience_comments' then
     'Shared-experience comments inherit shared parent but archived comments are visible only to original author; remove replies to hidden comments. Preserve written text, exclude media. Reference-only history; no restoration into next relationship.'
   else
     'Shared-experience revision audit trail inherits shared parent, includes both member contributions with media-free before/after snapshots. Reference-only history; never restore as a live record.'
 end
where source_table in ('shared_experience_comments',
                       'shared_experience_revisions')
  and relation_kind='dependent'
  and canonical_parent='shared_experiences'
  and disposition='review_required'
  and not approved;

create or replace function private.qa_shared_experience_history_preview(
 p_experience_id uuid
) returns jsonb
language plpgsql stable security definer set search_path='' as $fn$
declare
 caller uuid:=auth.uid();
 root public.shared_experiences%rowtype;
 notes jsonb;
 history jsonb;
 nc integer;
 nr integer;
 unknown_authors bigint;
 payload jsonb;
begin
 if caller is null then raise exception 'Sign in required';end if;
 select x.* into root
 from public.shared_experiences x
 join public.space_members m
   on m.space_id=x.space_id and m.user_id=caller
 where x.id=p_experience_id;
 if not found then raise exception 'Shared experience not found'; end if;
 if (select count(*) from public.space_members where user_id=caller)<>1 then
   raise exception 'Shared experience not found';
 end if;
 if (select count(*) from private.qa_archive_table_policy p
    where p.source_table in ('shared_experiences',
       'shared_experience_comments','shared_experience_revisions')
     and p.approved and p.disposition='shared_only')<>3 then
    raise exception 'Shared-experience history scope not approved';end if;
 -- Any current child authored by a user outside the couple is an integrity
 -- fault. Do not silently drop it from the archive's completeness counts.
 select count(*) into unknown_authors
 from public.shared_experience_comments c
 where c.experience_id=root.id
   and not exists(select 1 from public.space_members sm
     where sm.space_id=root.space_id and sm.user_id=c.created_by);
 if unknown_authors>0 then
   raise exception 'Shared-experience comment owner lineage mismatch';end if;
 select count(*) into unknown_authors
 from public.shared_experience_revisions r
 where r.experience_id=root.id
   and r.changed_by is not null
   and not exists(select 1 from public.space_members sm
     where sm.space_id=root.space_id and sm.user_id=r.changed_by);
 if unknown_authors>0 then
   raise exception 'Shared-experience revision author lineage mismatch';end if;
 select count(*) into nc
 from public.shared_experience_comments c
 where c.experience_id=root.id
   and (c.archived_at is null or c.created_by=caller);
 select count(*) into nr
 from public.shared_experience_revisions r
 where r.experience_id=root.id;
 if nc+nr>500 then
   raise exception 'Shared-experience history exceeds 500 records';end if;
 -- Do not keep a reply UUID if it would point to an archived comment that
 -- the recipient was not permitted to see.
 select coalesce(jsonb_agg(
   jsonb_build_object('source_id',c.id,
     'structured',
       case when c.reply_to is not null and not exists (
         select 1 from public.shared_experience_comments parent
          where parent.id=c.reply_to and parent.experience_id=root.id
            and (parent.archived_at is null or parent.created_by=caller))
       then private.qa_structured_value(to_jsonb(c))-'reply_to'
       else private.qa_structured_value(to_jsonb(c)) end)
   order by c.created_at,c.id),'[]'::jsonb)
 into notes
 from public.shared_experience_comments c
 where c.experience_id=root.id
   and (c.archived_at is null or c.created_by=caller);
 select coalesce(jsonb_agg(
     jsonb_build_object('source_id',r.id,
       'structured',private.qa_structured_value(to_jsonb(r)))
     order by r.changed_at,r.id),'[]'::jsonb)
 into history
 from public.shared_experience_revisions r
 where r.experience_id=root.id;
 payload:=jsonb_build_object(
   'schema','onespace.shared-experience-history-preview.v1',
   'kind','shared_reference_only',
   'recipient_id',caller,'source_space_id',root.space_id,
   'root',jsonb_build_object('table','shared_experiences',
     'source_id',root.id,
     'structured',private.qa_structured_value(to_jsonb(root))),
   'comments',notes,'revisions',history,
   'visible_comment_count',nc,'revision_count',nr
 );
 if octet_length(convert_to(payload::text,'UTF8'))>2097152 then
   raise exception 'Shared-experience history exceeds 2 MiB';end if;
 return jsonb_build_object('payload',payload,
   'payload_sha256',encode(extensions.digest(
     convert_to(payload::text,'UTF8'),'sha256'),'hex'),
   'media_included',false,'documents_included',false,
   'encrypted',false,'is_verified_archive',false,
   'can_restore',false,'safe_to_separate',false,
   'warning','Shared written history is reference-only; archived comments are visible only to their authors. This is not an encrypted archive.');
end $fn$;
revoke all on function private.qa_shared_experience_history_preview(uuid)
 from public,anon,authenticated;
grant execute on function private.qa_shared_experience_history_preview(uuid)
 to authenticated;
-- Global archive/lifecycle readiness remains FALSE.
