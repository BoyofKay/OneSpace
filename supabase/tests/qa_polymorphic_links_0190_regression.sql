begin;
do $qa$
declare sid uuid;a uuid;b uuid;foreign_space uuid;
 shared_note uuid; private_note uuid; shared_task uuid; private_task uuid;
 shared_link uuid; private_link uuid; p jsonb; err text;
begin
 select s.id,s.created_by,m.user_id into sid,a,b from public.spaces s
 join public.space_members m on m.space_id=s.id and m.user_id<>s.created_by
 where (select count(*) from public.space_members x where x.space_id=s.id)=2 limit 1;
 if sid is null then raise exception 'QA pair required';end if;
 select id into foreign_space from public.spaces where id<>sid limit 1;
 insert into public.notes(space_id,created_by,title,visibility)
 values(sid,a,'QA shared link note','shared') returning id into shared_note;
 insert into public.notes(space_id,created_by,title,visibility)
 values(sid,a,'QA owner-only link note','private') returning id into private_note;
 insert into public.tasks(space_id,created_by,title,visibility)
 values(sid,b,'QA shared linked task','shared') returning id into shared_task;
 insert into public.tasks(space_id,created_by,title,visibility)
 values(sid,a,'QA private linked task','private') returning id into private_task;
 insert into public.note_references(note_id,target_kind,target_id,created_by)
 values(shared_note,'task',shared_task,a),(private_note,'task',private_task,a);
 insert into public.item_links(space_id,from_kind,from_id,to_kind,to_id,created_by)
 values(sid,'note',shared_note,'task',shared_task,a)
 returning id into shared_link;
 insert into public.item_links(space_id,from_kind,from_id,to_kind,to_id,created_by)
 values(sid,'note',private_note,'task',private_task,a)
 returning id into private_link;
 if has_function_privilege('anon','private.qa_portable_target_scope(text,uuid,uuid,uuid)','execute')
 or has_function_privilege('authenticated','private.qa_portable_target_scope(text,uuid,uuid,uuid)','execute')
 or has_function_privilege('anon','private.qa_note_reference_history_preview(uuid)','execute')
 or has_function_privilege('anon','private.qa_item_link_history_preview(uuid)','execute')
 then raise exception 'Raw polymorphic scope leaks through execute grants';end if;
 perform set_config('role','authenticated',true);
 perform set_config('request.jwt.claim.sub',a::text,true);
 p:=private.qa_note_reference_history_preview(shared_note);
 if p#>>'{payload,kind}'<>'shared_reference_only'
 or p#>>'{payload,link_count}'<>'1'
 or p::text not like '%QA shared link note%'
 then raise exception 'Shared note historical links missing';end if;
 p:=private.qa_note_reference_history_preview(private_note);
 if p#>>'{payload,kind}'<>'private_owner_only'
 or p#>>'{payload,link_count}'<>'1'
 or p->>'can_restore'<>'false'
 then raise exception 'Owner-private note link failed';end if;
 p:=private.qa_item_link_history_preview(private_link);
 if p#>>'{payload,kind}'<>'private_owner_only'
 or p->>'is_verified_archive'<>'false'
 then raise exception 'Owner private link missing';end if;
 if p->>'payload_sha256'<>encode(extensions.digest(convert_to((p->'payload')::text,'UTF8'),'sha256'),'hex')
 then raise exception 'Link integrity digest mismatch';end if;
 perform set_config('request.jwt.claim.sub',b::text,true);
 p:=private.qa_note_reference_history_preview(shared_note);
 if p#>>'{payload,link_count}'<>'1' then raise exception 'Partner lost shared note link';end if;
 p:=private.qa_item_link_history_preview(shared_link);
 if p#>>'{payload,kind}'<>'shared_reference_only'
 then raise exception 'Partner lost shared item link';end if;
 begin
 perform private.qa_note_reference_history_preview(private_note);
 raise exception 'Partner accessed owner-private note reference';
 exception when others then
 get stacked diagnostics err=message_text;
 if err<>'Note not found' then raise exception 'Wrong partner note denial: %',err;end if;
 end;
 begin
 perform private.qa_item_link_history_preview(private_link);
 raise exception 'Partner accessed private item link';
 exception when others then
 get stacked diagnostics err=message_text;
 if err<>'Link not found' then raise exception 'Wrong partner link denial: %',err;end if;
 end;

 -- Malicious previously shared note reference now points to private
 -- target; neither partner may export a shared link that leaks private IDs.
 perform set_config('role','postgres',true);
 insert into public.note_references(note_id,target_kind,target_id,created_by)
 values(shared_note,'task',private_task,a);
 perform set_config('role','authenticated',true);
 perform set_config('request.jwt.claim.sub',a::text,true);
 begin
 perform private.qa_note_reference_history_preview(shared_note);
 raise exception 'Shared note exported private target';
 exception when others then
 get stacked diagnostics err=message_text;
 if err<>'Note target visibility, author or space mismatch' then
 raise exception 'Wrong mixed-visibility link denial: %',err;end if;
 end;
 if foreign_space is not null then
   perform set_config('role','postgres',true);
   insert into public.tasks(space_id,created_by,title,visibility)
   values(foreign_space,a,'QA foreign space task','private') returning id into private_task;
   insert into public.item_links(space_id,from_kind,from_id,to_kind,to_id,created_by)
   values(sid,'note',private_note,'task',private_task,a)
   returning id into private_link;
   perform set_config('role','authenticated',true);
   begin
   perform private.qa_item_link_history_preview(private_link);
   raise exception 'Cross-space polymorphic association accepted';
   exception when others then
   get stacked diagnostics err=message_text;
   if err<>'Link not found' then raise exception 'Wrong cross-space denial: %',err;end if;
   end;
 end if;
end $qa$;
rollback;
select 'PASS: same-space polymorphic owner/shared links, hidden private target denial, private note/references, anonymous helper privileges, cross-space collision; rolled back' result;