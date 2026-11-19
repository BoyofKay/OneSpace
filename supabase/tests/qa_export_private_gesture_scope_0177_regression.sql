-- QA rollback-only regression: creator-private gesture drafts and
-- sender-private schedules never leak through SECURITY DEFINER data export.
begin;
do $qa$
declare
 sid uuid; a uuid; b uuid;
 export_a jsonb; export_b jsonb;
begin
 select s.id,s.created_by,m.user_id into sid,a,b
 from public.spaces s join public.space_members m
 on m.space_id=s.id and m.user_id<>s.created_by
 where (select count(*) from public.space_members sm where sm.space_id=s.id)=2
 limit 1;
 if sid is null then raise exception 'Paired QA fixture missing';end if;

 insert into public.gesture_templates(
   space_id,creator_id,recipient_id,kind,title,message)
 values(sid,a,b,'hug','QA-A-PRE-SEND-TITLE','QA A UNSENT PRIVATE TEMPLATE'),
       (sid,b,a,'hug','QA-B-PRE-SEND-TITLE','QA B UNSENT PRIVATE TEMPLATE');
 insert into public.gesture_schedules(
   space_id,sender_id,recipient_id,moment,enabled)
 values(sid,a,b,'morning',true),(sid,b,a,'after_work',true);
 insert into public.notes(space_id,created_by,title,body,visibility,rich_delta)
 values(sid,a,'QA-A-MEDIA-SANITIZE','Written note before and after a media upload',
 'private','[{"insert":"keep prose"},{"insert":{"image":"data:image/png;base64,QQQ"}}]'::jsonb);

 if has_function_privilege('anon','public.export_my_data()','execute') then
   raise exception 'Anonymous JSON export must be blocked';
 end if;
 perform set_config('role','authenticated',true);
 perform set_config('request.jwt.claim.sub',a::text,true);
 export_a:=public.export_my_data();
 if export_a::text not like '%QA A UNSENT PRIVATE TEMPLATE%'
 or export_a::text like '%QA B UNSENT PRIVATE TEMPLATE%'
 or jsonb_array_length(export_a->'gesture_templates')<>1
 or jsonb_array_length(export_a->'gesture_schedules')<>1
 or (export_a->'gesture_schedules'->0->>'sender_id')<>a::text then
   raise exception 'Owner A export leaked B private gesture data: %',
       left(export_a::text,400);
 end if;
 if export_a::text like '%data:image%'
 or export_a::text like '%base64%'
 or export_a::text not like '%keep prose%'
 or export_a::text not like '%Written note before and after%' then
   raise exception 'Media sanitized export lost prose or retained media';
 end if;

 perform set_config('request.jwt.claim.sub',b::text,true);
 export_b:=public.export_my_data();
 if export_b::text not like '%QA B UNSENT PRIVATE TEMPLATE%'
 or export_b::text like '%QA A UNSENT PRIVATE TEMPLATE%'
 or jsonb_array_length(export_b->'gesture_templates')<>1
 or jsonb_array_length(export_b->'gesture_schedules')<>1
 or (export_b->'gesture_schedules'->0->>'sender_id')<>b::text
 or export_b::text like '%QA-A-MEDIA-SANITIZE%' then
   raise exception 'Owner B export leaked A private content';
 end if;
end $qa$;
rollback;
select 'PASS: paired users export only self-created gesture templates and self-sent schedules; private notes sanitized; anon denied, fixtures rolled back' as result;
