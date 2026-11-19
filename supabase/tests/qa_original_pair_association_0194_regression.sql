begin;
do $qa$
declare sid uuid; a uuid; b uuid; outsider uuid; valid_task uuid; foreign_task uuid; invalid_link uuid;
 scope text; err text;
begin
 select s.id,s.created_by,m.user_id into sid,a,b from public.spaces s
 join public.space_members m on m.space_id=s.id and m.user_id<>s.created_by
 where (select count(*) from public.space_members x where x.space_id=s.id)=2 limit 1;
 if sid is null then raise exception 'QA original pair missing';end if;
 select id into outsider from auth.users u where u.id not in
 (select user_id from public.space_members sm where sm.space_id=sid) limit 1;
 if outsider is null then raise exception 'Outsider fixture required';end if;
 perform set_config('request.jwt.claim.sub',a::text,true);
 insert into public.tasks(space_id,created_by,title,visibility)
 values(sid,a,'QA legitimate shared owner','shared') returning id into valid_task;
 insert into public.tasks(space_id,created_by,title,visibility)
 values(sid,outsider,'QA historic foreign creator','shared') returning id into foreign_task;
 scope:=private.qa_portable_target_scope('task',valid_task,sid,a);
 if scope<>'shared' then raise exception 'Legitimate pair-owned shared task was blocked';end if;
 scope:=private.qa_portable_target_scope('task',foreign_task,sid,a);
 if scope<>'blocked' then raise exception 'Former partner author was accepted as active pair';end if;
 scope:=private.qa_action_history_record_scope('task',foreign_task,sid,a);
 if scope<>'blocked' then raise exception 'Foreign task was accepted through audit history';end if;
 insert into public.item_links(space_id,from_kind,from_id,to_kind,to_id,created_by)
 values(sid,'task',valid_task,'task',foreign_task,a) returning id into invalid_link;
 perform set_config('role','authenticated',true);
 begin
  perform private.qa_item_link_history_preview(invalid_link);
  raise exception 'Foreign-creator link visible';
 exception when others then
  get stacked diagnostics err=message_text;
  if err<>'Link not found' then raise exception 'Unexpected foreign link result %',err;end if;
 end;
end $qa$;
rollback;
select 'PASS: original-pair author lineage enforced for shared target, action history and polymorphic links; foreign authored fixture rolled back' result;