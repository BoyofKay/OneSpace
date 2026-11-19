-- QA-only signed-in snapshot preview regression. No permanent writes.
begin;
do $test$
declare
 sid uuid;
 v_owner uuid;
 v_partner uuid;
 owner_private uuid;
 partner_private uuid;
 shared_note uuid;
 p jsonb;
 s jsonb;
 err text;
begin
 select sp.id,sp.created_by,sm.user_id into sid,v_owner,v_partner
 from public.spaces sp join public.space_members sm
   on sm.space_id=sp.id and sm.user_id<>sp.created_by
 where (select count(*) from public.space_members k where k.space_id=sp.id)=2
 limit 1;
 if sid is null then raise exception 'Missing paired QA test space'; end if;
 if has_function_privilege('anon','public.my_structured_archive_preview(text)','execute') then
   raise exception 'Anonymous preview execution must be denied';
 end if;
 insert into public.notes(space_id,created_by,title,body,visibility,rich_delta)
 values(sid,v_owner,'Owner private','Owner-only structured note','private',
       '[{"insert":"Private text"},{"insert":{"image":"data:image/png;base64,QQQ"}}]'::jsonb)
 returning id into owner_private;
 insert into public.notes(space_id,created_by,title,body,visibility)
 values(sid,v_partner,'Partner private','Partner secret','private')
 returning id into partner_private;
 insert into public.notes(space_id,created_by,title,body,visibility)
 values(sid,v_owner,'Couple shared note','Shared structured story','shared')
 returning id into shared_note;

 perform set_config('role','authenticated',true);
 perform set_config('request.jwt.claim.sub',v_owner::text,true);
 p:=public.my_structured_archive_preview('private');
 s:=public.my_structured_archive_preview('shared');
 if (p->>'recipient_id')<>v_owner::text
    or (p->>'record_count')::int<>1
    or p::text not like '%Owner-only structured note%'
    or p::text like '%Partner secret%'
    or p::text like '%data:image%'
    or p->>'is_verified_archive'<>'false'
    or s::text not like '%Shared structured story%'
    or s::text like '%Partner secret%' then
   raise exception 'Owner private/shared preview isolation failed';
 end if;
 perform set_config('request.jwt.claim.sub',v_partner::text,true);
 p:=public.my_structured_archive_preview('private');
 s:=public.my_structured_archive_preview('shared');
 if (p->>'record_count')::int<>1 or
    p::text not like '%Partner secret%' or
    p::text like '%Owner-only structured note%' or
    s::text not like '%Shared structured story%' then
   raise exception 'Partner private/shared preview isolation failed';
 end if;
 begin
   perform public.my_structured_archive_preview('unscoped');
   raise exception 'Invalid archive kind was allowed';
 exception when others then
   get stacked diagnostics err=message_text;
   if err not like 'Archive kind must be private or shared%' then
     raise exception 'Unexpected invalid-kind response: %',err;
   end if;
 end;
end $test$;
rollback;
select 'PASS: two-member private isolation, shared visibility, media exclusion, invalid scope denial, anon denial; synthetic rows rolled back' result;
