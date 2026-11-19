-- QA rollback-only shared experience written history and recipient privacy.
begin;
do $qa$
declare
  sid uuid; a uuid; b uuid; outsider uuid;
  expid uuid; hidden_b uuid;
  response jsonb; as_a jsonb; as_b jsonb; err text; digest text;
begin
 select s.id,s.created_by,m.user_id into sid,a,b
  from public.spaces s join public.space_members m
  on m.space_id=s.id and m.user_id<>s.created_by
  where (select count(*) from public.space_members sm where sm.space_id=s.id)=2
  limit 1;
 if sid is null then raise exception 'Paired QA fixture missing';end if;
 select u.id into outsider from auth.users u where u.id not in
  (select user_id from public.space_members where space_id=sid) limit 1;
 insert into public.shared_experiences(
   space_id,created_by,category,title,description,source_url)
 values(sid,a,'movie','QA SHARED EXPERIENCE ARCHIVE',
   'A memory worth preserving','https://example.org/movie')
 returning id into expid;
 insert into public.shared_experience_comments(
   experience_id,created_by,body,archived_at)
 values(expid,b,'B ARCHIVED PERSONAL COMMENT',now())
 returning id into hidden_b;
 insert into public.shared_experience_comments(
   experience_id,created_by,body,reply_to)
 values(expid,a,'A WRITTEN REPLY',hidden_b);
 insert into public.shared_experience_revisions(
   experience_id,changed_by,before_snapshot,after_snapshot)
 values(expid,b,
   jsonb_build_object('description','Old written description',
     'photo_1_id','aabbccdd-1111-4444-8888-123456789123'),
   jsonb_build_object('description',
     'Keep this new text, image https://x.invalid/storage/v1/object/public/file.jpg'));

 if (select count(*) from private.qa_archive_table_policy
   where source_table in ('shared_experience_comments',
      'shared_experience_revisions') and approved and disposition='shared_only')<>2 then
   raise exception 'Shared experience child classifications incomplete';end if;
 if has_function_privilege('anon',
   'private.qa_shared_experience_history_preview(uuid)','execute') then
   raise exception 'Anonymous history preview executable';end if;

 perform set_config('role','authenticated',true);
 perform set_config('request.jwt.claim.sub',a::text,true);
 response:=private.qa_shared_experience_history_preview(expid);
 as_a:=response->'payload';
 if as_a->>'recipient_id'<>a::text
   or as_a->>'kind'<>'shared_reference_only'
   or jsonb_array_length(as_a->'comments')<>1
   or (as_a#>>'{comments,0,structured,body}')<>'A WRITTEN REPLY'
   or (as_a#>'{comments,0,structured}') ? 'reply_to'
   or response::text like '%B ARCHIVED PERSONAL COMMENT%'
   or (as_a->>'revision_count')::int<>1
   or response::text like '%storage/v1/object%'
   or response::text like '%photo_1_id%'
   or response::text not like '%Old written description%'
   or response->>'can_restore'<>'false'
   or response->>'is_verified_archive'<>'false'
 then raise exception 'A received unauthorized archived B comment or missing text: %',left(response::text,900);end if;
 digest:=encode(extensions.digest(convert_to(as_a::text,'UTF8'),'sha256'),'hex');
 if response->>'payload_sha256'<>digest then
   raise exception 'A shared history checksum mismatch';end if;

 perform set_config('request.jwt.claim.sub',b::text,true);
 response:=private.qa_shared_experience_history_preview(expid);
 as_b:=response->'payload';
 if jsonb_array_length(as_b->'comments')<>2
   or response::text not like '%B ARCHIVED PERSONAL COMMENT%'
   or response::text not like '%A WRITTEN REPLY%'
   or not (as_b#>'{comments,1,structured}' ? 'reply_to')
 then raise exception 'B lost own archived comment or reply lineage';end if;

 select u.id into outsider from auth.users u where u.id not in
  (select user_id from public.space_members where space_id=sid) limit 1;
 if outsider is not null then
   perform set_config('request.jwt.claim.sub',outsider::text,true);
   begin
     perform private.qa_shared_experience_history_preview(expid);
     raise exception 'External account accessed relationship history';
   exception when others then
     get stacked diagnostics err=message_text;
     if err<>'Shared experience not found' then
       raise exception 'Wrong outside-account denial: %',err;end if;
   end;
 end if;

 perform set_config('role','postgres',true);
 if outsider is not null then
   insert into public.shared_experience_revisions(
     experience_id,changed_by,before_snapshot,after_snapshot)
   values(expid,outsider,'{}'::jsonb,'{}'::jsonb);
   perform set_config('role','authenticated',true);
   perform set_config('request.jwt.claim.sub',a::text,true);
   begin
     perform private.qa_shared_experience_history_preview(expid);
     raise exception 'Outsider revision was silently archived';
   exception when others then
     get stacked diagnostics err=message_text;
     if err<>'Shared-experience revision author lineage mismatch' then
       raise exception 'Wrong orphan revision denial: %',err;end if;
   end;
 end if;
end $qa$;
rollback;
select 'PASS: shared experiences recipient-specific archived comment privacy, safe thread references, media-free revisions, SHA-256 and outsider rejection; rolled back' result;
