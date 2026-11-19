-- QA 0183: six activity descendants, both members, private owner, media
-- scrubbing, collision denial and stable SHA-256. All fixtures rolled back.
begin;
do $qa$
declare
 sid uuid; a uuid; b uuid; outsider uuid;
 activity_id uuid; private_id uuid; component_id uuid;
 preview jsonb; payload jsonb; msg text;
begin
 select s.id,s.created_by,m.user_id into sid,a,b
 from public.spaces s join public.space_members m
 on m.space_id=s.id and m.user_id<>s.created_by
 where (select count(*) from public.space_members x where x.space_id=s.id)=2
 limit 1;
 if sid is null then raise exception 'Paired QA fixture missing';end if;
 select u.id into outsider from auth.users u where u.id not in
   (select user_id from public.space_members where space_id=sid) limit 1;
 insert into public.activities(space_id,created_by,title,body,visibility)
 values(sid,a,'QA ARCHIVED ACTIVITY','What should we do together?','shared')
 returning id into activity_id;
 insert into public.activity_components(
    activity_id,created_by,kind,label,payload)
 values(activity_id,b,'image','Caption about our photo',
   '{"object_path":"media-storage-path-private",
     "caption":"We went to the park",
     "photo_1_id":"77777777-2222-4333-8444-555555555555"}'::jsonb)
 returning id into component_id;
 insert into public.activity_comments(activity_id,author_id,body)
 values(activity_id,a,'We made a lovely plan');
 insert into public.activity_component_reactions(
     activity_id,component_id,user_id,opinion)
 values(activity_id,component_id,b,1);
 insert into public.activity_decisions(
     activity_id,component_id,action,reason,created_by)
 values(activity_id,component_id,'chosen','We agreed together',a);
 insert into public.activity_component_revisions(
     activity_id,component_id,changed_by,old_label,new_label,
     old_payload,new_payload)
 values(activity_id,component_id,b,'Old choice','New choice',
    '{"file_path":"hidden-object","caption":"Old caption"}'::jsonb,
    '{"voice_path":"uploaded.m4a","caption":"New caption"}'::jsonb);
 insert into public.activity_revisions(
   activity_id,changed_by,old_title,new_title,old_body,new_body,
   old_stage,new_stage,old_priority,new_priority)
 values(activity_id,a,'Before title','After title',
    'Before message','After message','idea','decided','normal','high');

 if has_function_privilege('anon',
   'private.qa_activity_nested_structured_preview(uuid)','execute')
 then raise exception 'Anonymous activity preview executable';end if;
 perform set_config('role','authenticated',true);
 perform set_config('request.jwt.claim.sub',a::text,true);
 preview:=private.qa_activity_nested_structured_preview(activity_id);
 payload:=preview->'payload';
 if payload#>>'{kind}'<>'shared_reference_only'
   or payload#>>'{child_record_count}'<>'6'
   or jsonb_array_length(payload#>'{children,activity_components}')<>1
   or jsonb_array_length(payload#>'{children,activity_comments}')<>1
   or jsonb_array_length(payload#>'{children,activity_component_reactions}')<>1
   or jsonb_array_length(payload#>'{children,activity_decisions}')<>1
   or jsonb_array_length(payload#>'{children,activity_component_revisions}')<>1
   or jsonb_array_length(payload#>'{children,activity_revisions}')<>1
   or preview::text not like '%We went to the park%'
   or preview::text not like '%New caption%'
   or preview::text not like '%We made a lovely plan%'
   or preview::text like '%media-storage-path-private%'
   or preview::text like '%uploaded.m4a%'
   or preview::text like '%photo_1_id%'
   or preview->>'can_restore'<>'false'
 then raise exception 'Activity preview incomplete or media leaked: %',
      left(preview::text,1900);end if;
 if preview->>'payload_sha256' <>
    encode(extensions.digest(
     convert_to(payload::text,'UTF8'),'sha256'),'hex')
 then raise exception 'Activity SHA-256 checksum inconsistent';end if;
 perform set_config('request.jwt.claim.sub',b::text,true);
 preview:=private.qa_activity_nested_structured_preview(activity_id);
 if preview#>>'{payload,recipient_id}'<>b::text
   or preview#>>'{payload,child_record_count}'<>'6'
 then raise exception 'Shared history excluded active partner';end if;
 if outsider is not null then
   perform set_config('request.jwt.claim.sub',outsider::text,true);
   begin
     perform private.qa_activity_nested_structured_preview(activity_id);
     raise exception 'Outsider accessed pair activity';
   exception when others then
     get stacked diagnostics msg=message_text;
     if msg<>'Activity preview not found' then
       raise exception 'Unexpected outsider outcome: %',msg;end if;
   end;
 end if;

 perform set_config('role','postgres',true);
 insert into public.activities(space_id,created_by,title,visibility)
 values(sid,a,'QA PRIVATE ACTIVITY','private') returning id into private_id;
 insert into public.activity_comments(activity_id,author_id,body)
 values(private_id,a,'Private conversation line');
 perform set_config('role','authenticated',true);
 perform set_config('request.jwt.claim.sub',a::text,true);
 preview:=private.qa_activity_nested_structured_preview(private_id);
 if preview#>>'{payload,kind}'<>'private_owner_only'
   or preview#>>'{payload,child_record_count}'<>'1'
 then raise exception 'Owner private activity failed preview';end if;
 perform set_config('request.jwt.claim.sub',b::text,true);
 begin
   perform private.qa_activity_nested_structured_preview(private_id);
   raise exception 'Partner exported private activity';
 exception when others then
   get stacked diagnostics msg=message_text;
   if msg<>'Activity preview not found' then
     raise exception 'Wrong partner privacy outcome: %',msg;end if;
 end;

 -- An old shared activity with partner-authored children cannot be silently
 -- made a portable private owner archive by flipping its visibility.
 perform set_config('role','postgres',true);
 update public.activities set visibility='private' where id=activity_id;
 perform set_config('role','authenticated',true);
 perform set_config('request.jwt.claim.sub',a::text,true);
 begin
   perform private.qa_activity_nested_structured_preview(activity_id);
   raise exception 'Partner-authored component illegally became private';
 exception when others then
   get stacked diagnostics msg=message_text;
   if msg not like 'Activity child contributor lineage mismatch:%' then
     raise exception 'Wrong cross-owner guard: %',msg;end if;
 end;
end $qa$;
rollback;
select 'PASS: all six activity child families, pair/private isolation, no media paths, written captions, checksum and re-private collision denial; rolled back' result;
