begin;
do $qa$
declare sid uuid;a uuid;b uuid;
 note_id uuid;activity_id uuid;experience_id uuid;comment_id uuid;request_id uuid;
 own_event bigint;shared_event bigint;foreign_event bigint;archived_event bigint;checkin_event bigint;missing_event bigint;
 p jsonb; err text; kind text; kinds text[]:=array[
 'note','task','goal','memory','event','reminder','occasion','experience','trip',
 'contact','checkin','checkin_request','experience_comment','sort_item','activity'];
begin
 select s.id,s.created_by,m.user_id into sid,a,b from public.spaces s
 join public.space_members m on m.space_id=s.id and m.user_id<>s.created_by
 where (select count(*) from public.space_members x where x.space_id=s.id)=2 limit 1;
 if sid is null then raise exception 'QA pair missing';end if;
 insert into public.notes(space_id,created_by,title,body,visibility)
 values(sid,a,'QA private audited note','Private written details','private') returning id into note_id;
 insert into public.activities(space_id,created_by,title,visibility)
 values(sid,a,'QA audited shared activity','shared') returning id into activity_id;
 insert into public.shared_experiences(space_id,created_by,category,title)
 values(sid,a,'movie','QA experienced story') returning id into experience_id;
 insert into public.shared_experience_comments(experience_id,created_by,body,archived_at)
 values(experience_id,b,'B private archived text',now()) returning id into comment_id;
 insert into public.partner_checkin_requests(space_id,sender_id,recipient_id,note)
 values(sid,a,b,'QA old shared check-in') returning id into request_id;

 insert into public.record_action_history(space_id,record_kind,record_id,actor_id,action,changed_fields)
 values(sid,'note',note_id,a,'edited',array['body']) returning id into own_event;
 insert into public.record_action_history(space_id,record_kind,record_id,actor_id,action,changed_fields)
 values(sid,'activity',activity_id,b,'edited',array['title']) returning id into shared_event;
 insert into public.record_action_history(space_id,record_kind,record_id,actor_id,action,changed_fields)
 values(sid,'note',note_id,b,'edited',array['title']) returning id into foreign_event;
 insert into public.record_action_history(space_id,record_kind,record_id,actor_id,action,changed_fields)
 values(sid,'experience_comment',comment_id,b,'archived',array['archived_at']) returning id into archived_event;
 insert into public.record_action_history(space_id,record_kind,record_id,actor_id,action,changed_fields)
 values(sid,'checkin_request',request_id,a,'created',array['note']) returning id into checkin_event;
 insert into public.record_action_history(space_id,record_kind,record_id,actor_id,action,changed_fields)
 values(sid,'note',gen_random_uuid(),a,'edited',array['body']) returning id into missing_event;
 if has_function_privilege('anon','private.qa_record_action_history_preview(bigint)','execute')
 or has_function_privilege('authenticated','private.qa_action_history_record_scope(text,uuid,uuid,uuid)','execute')
 then raise exception 'Internal history scope externally executable';end if;
 perform set_config('role','authenticated',true);
 perform set_config('request.jwt.claim.sub',a::text,true);
 p:=private.qa_record_action_history_preview(own_event);
 if p#>>'{payload,kind}'<>'private_owner_only'
 or p#>>'{payload,event,action}'<>'edited'
 or p->>'can_restore'<>'false'
 then raise exception 'Private audit history lost or became restorable';end if;
 if p->>'payload_sha256'<>encode(extensions.digest(convert_to((p->'payload')::text,'UTF8'),'sha256'),'hex')
 then raise exception 'Action history digest mismatch';end if;
 p:=private.qa_record_action_history_preview(shared_event);
 if p#>>'{payload,kind}'<>'shared_reference_only'
 then raise exception 'Shared activity history missing';end if;
 p:=private.qa_record_action_history_preview(checkin_event);
 if p#>>'{payload,kind}'<>'shared_reference_only'
 then raise exception 'Check-in request audit missing';end if;
 for p in select jsonb_build_object('id',id) from
 (values (foreign_event),(archived_event),(missing_event)) ids(id) loop
 begin
 perform private.qa_record_action_history_preview((p->>'id')::bigint);
 raise exception 'Unsafe audit action was exported';
 exception when others then
 get stacked diagnostics err=message_text;
 if err not in ('Private record audit actor mismatch','History action not found')
 then raise exception 'Unexpected denied-audit error %',err;end if;
 end;
 end loop;
 perform set_config('request.jwt.claim.sub',b::text,true);
 p:=private.qa_record_action_history_preview(shared_event);
 if p#>>'{payload,kind}'<>'shared_reference_only' then
 raise exception 'Second member lost shared activity audit';end if;
 p:=private.qa_record_action_history_preview(archived_event);
 if p#>>'{payload,kind}'<>'private_owner_only'
 then raise exception 'Author lost own archived comment audit';end if;
 begin
 perform private.qa_record_action_history_preview(own_event);
 raise exception 'Second member saw partner private note audit';
 exception when others then
 get stacked diagnostics err=message_text;
 if err<>'History action not found' then
 raise exception 'Wrong partner-private audit failure %',err;end if;
 end;
 perform set_config('role','postgres',true);
 perform set_config('request.jwt.claim.sub',a::text,true);
 foreach kind in array kinds loop
 if private.qa_action_history_record_scope(kind,gen_random_uuid(),sid,a)<>'blocked'
 then raise exception 'Nonexistent % history parent was accepted',kind;end if;
 end loop;
 if private.qa_action_history_record_scope('not_a_kind',note_id,sid,a)<>'blocked'
 then raise exception 'Unknown history category accepted';end if;
end $qa$;
rollback;
select 'PASS: all 15 event kinds deny missing records, private note actors, shared pair audit, author-only archived comments, check-in, no orphan pointers, SHA-256; rolled back' result;