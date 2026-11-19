begin;
do $qa$
declare sid uuid; a uuid; b uuid; root_id uuid; private_id uuid; p jsonb; err text;
begin
 select s.id,s.created_by,m.user_id into sid,a,b from public.spaces s
 join public.space_members m on m.space_id=s.id and m.user_id<>s.created_by
 where (select count(*) from public.space_members t where t.space_id=s.id)=2 limit 1;
 if sid is null then raise exception 'QA pair missing';end if;
 insert into public.reminders(space_id,created_by,title,due_at,visibility,audience)
 values(sid,a,'QA shared reminder history',now()+interval '1 day','shared','both') returning id into root_id;
 update public.reminder_recipients set state='done',outcome_note='Thank you for the reminder',snoozed_until=now()+interval '2 hours' where reminder_id=root_id and recipient_id=b;
 insert into public.reminder_actions(reminder_id,recipient_id,actor_id,action,note,next_alert_at)
 values(root_id,b,b,'done','We finished that together',now()+interval '2 hours');
 insert into public.reminders(space_id,created_by,title,due_at,visibility,audience)
 values(sid,a,'QA my private reminder',now()+interval '2 days','private','me') returning id into private_id;
 update public.reminder_recipients set state='done',outcome_note='My private completion note' where reminder_id=private_id and recipient_id=a;
 if has_function_privilege('anon','private.qa_reminder_written_history_preview(uuid)','execute')
 then raise exception 'Anon could export reminders';end if;
 perform set_config('role','authenticated',true);
 perform set_config('request.jwt.claim.sub',a::text,true);
 p:=private.qa_reminder_written_history_preview(root_id);
 if p#>>'{payload,kind}'<>'shared_reference_only'
 or p#>>'{payload,child_record_count}'<>'2'
 or p::text not like '%We finished that together%'
 or p::text not like '%Thank you for the reminder%'
 or p::text like '%snoozed_until%'
 or p::text like '%next_alert_at%'
 or p->>'can_restore'<>'false'
 then raise exception 'Shared reminder history was unsafe %',left(p::text,1300);end if;
 if p->>'payload_sha256'<>encode(extensions.digest(convert_to((p->'payload')::text,'UTF8'),'sha256'),'hex')
 then raise exception 'Reminder digest invalid';end if;
 p:=private.qa_reminder_written_history_preview(private_id);
 if p#>>'{payload,kind}'<>'private_owner_only' or p::text not like '%My private completion note%'
 then raise exception 'Owner private reminder missing';end if;
 perform set_config('request.jwt.claim.sub',b::text,true);
 p:=private.qa_reminder_written_history_preview(root_id);
 if p#>>'{payload,child_record_count}'<>'2' then raise exception 'Partner lost shared reminder';end if;
 begin
 perform private.qa_reminder_written_history_preview(private_id);
 raise exception 'Partner accessed private reminder';
 exception when others then
 get stacked diagnostics err=message_text;
 if err<>'Reminder not found' then raise exception 'Wrong private denial %',err;end if;
 end;
 perform set_config('role','postgres',true);
 update public.reminders set visibility='private' where id=root_id;
 perform set_config('role','authenticated',true);
 perform set_config('request.jwt.claim.sub',a::text,true);
 begin
 perform private.qa_reminder_written_history_preview(root_id);
 raise exception 'Partner recipient taken into owner private history';
 exception when others then
 get stacked diagnostics err=message_text;
 if err<>'Reminder recipient lineage mismatch' then raise exception 'Wrong recipient lineage denial %',err;end if;
 end;
end $qa$;
rollback;
select 'PASS: two reminder dependents, shared/private recipient author isolation, preserved written outcomes, transient schedule stripped and SHA-256; rolled back' result;