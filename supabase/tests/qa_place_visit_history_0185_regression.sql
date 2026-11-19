-- QA 0185: place/visit captions, shared collaborators, private re-parent
-- denial, memory link scrubbing and same-space FK integrity.
begin;
do $qa$
declare
 sid uuid; a uuid; b uuid; other uuid;
 shared_id uuid; private_id uuid; linked_memory uuid; linked_trip uuid;
 package jsonb; msg text;
begin
 select s.id,s.created_by,m.user_id into sid,a,b
 from public.spaces s join public.space_members m
   on m.space_id=s.id and m.user_id<>s.created_by
 where (select count(*) from public.space_members x where x.space_id=s.id)=2
 limit 1;
 if sid is null then raise exception 'Paired QA fixture required';end if;
 insert into public.memories(space_id,created_by,title,memory_date,visibility)
 values(sid,b,'QA private journal linked to visit',current_date,'private')
 returning id into linked_memory;
 insert into public.shared_trips(space_id,created_by,title,visibility)
 values(sid,a,'QA trip only linked by pointer','shared')
 returning id into linked_trip;
 insert into public.places(space_id,created_by,name,visibility,planned_trip_id)
 values(sid,a,'QA shared place history','shared',linked_trip)
 returning id into shared_id;
 insert into public.place_visits(
   place_id,space_id,created_by,visited_on,caption,memory_id)
 values(shared_id,sid,b,current_date,'A written story from visiting the cafe',
        linked_memory);
 insert into public.places(space_id,created_by,name,visibility)
 values(sid,a,'QA owner private place','private')
 returning id into private_id;
 insert into public.place_visits(
   place_id,space_id,created_by,visited_on,caption)
 values(private_id,sid,a,current_date,'A private written travel detail');

 if has_function_privilege('anon',
   'private.qa_place_visit_history_preview(uuid)','execute')
 then raise exception 'Anonymous place history executable';end if;
 perform set_config('role','authenticated',true);
 perform set_config('request.jwt.claim.sub',a::text,true);
 package:=private.qa_place_visit_history_preview(shared_id);
 if package#>>'{payload,kind}'<>'shared_reference_only'
   or package#>>'{payload,visit_count}'<>'1'
   or package::text not like '%A written story from visiting the cafe%'
   or package::text like '%'||linked_memory::text||'%'
   or package::text like '%'||linked_trip::text||'%'
   or package#>'{payload,root,structured}' ? 'planned_trip_id'
   or package#>'{payload,visits,0,structured}' ? 'memory_id'
   or package->>'can_restore'<>'false'
 then raise exception 'Shared place preview leaked unrelated private links: %',left(package::text,1200);end if;
 if package->>'payload_sha256' <>
   encode(extensions.digest(convert_to((package->'payload')::text,'UTF8'),'sha256'),'hex')
 then raise exception 'Place history hash mismatch';end if;
 package:=private.qa_place_visit_history_preview(private_id);
 if package#>>'{payload,kind}'<>'private_owner_only'
   or package::text not like '%A private written travel detail%' then
     raise exception 'Private place owner preservation failed';end if;
 perform set_config('request.jwt.claim.sub',b::text,true);
 package:=private.qa_place_visit_history_preview(shared_id);
 if package#>>'{payload,visit_count}'<>'1' then
   raise exception 'Partner lost shared visit record';end if;
 begin
   perform private.qa_place_visit_history_preview(private_id);
   raise exception 'Partner accessed private place';
 exception when others then
   get stacked diagnostics msg=message_text;
   if msg<>'Place not found' then raise exception 'Wrong partner denial: %',msg;end if;
 end;

 perform set_config('role','postgres',true);
 update public.places set visibility='private' where id=shared_id;
 perform set_config('role','authenticated',true);
 perform set_config('request.jwt.claim.sub',a::text,true);
 begin
   perform private.qa_place_visit_history_preview(shared_id);
   raise exception 'Shared partner visit silently became private owner history';
 exception when others then
   get stacked diagnostics msg=message_text;
   if msg<>'Place visit association or author mismatch' then
     raise exception 'Wrong private visit collision denial: %',msg;end if;
 end;
 -- A malicious cross-space association must also fail rather than becoming
 -- part of the current couple's history.
 select id into other from public.spaces where id<>sid limit 1;
 if other is not null then
   perform set_config('role','postgres',true);
   insert into public.place_visits(
     place_id,space_id,created_by,visited_on,caption)
   values(private_id,other,a,current_date,'Cross-space illegal visit link');
   perform set_config('role','authenticated',true);
   begin
     perform private.qa_place_visit_history_preview(private_id);
     raise exception 'Cross-space visit relation accepted';
   exception when others then
     get stacked diagnostics msg=message_text;
     if msg<>'Place visit association or author mismatch' then
       raise exception 'Wrong cross-space outcome: %',msg;end if;
   end;
 end if;
end $qa$;
rollback;
select 'PASS: private/shared place visits, no private memory/trip link leak, partner isolation, SHA-256, re-private and cross-space mismatch denial; rolled back' result;
