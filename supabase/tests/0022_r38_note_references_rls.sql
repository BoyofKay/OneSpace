-- R38 rollback-only two-partner privacy and link integrity regression.
begin;
select set_config('qa.space',space_id::text,true)
 from public.space_members group by space_id having count(*)=2 limit 1;
select set_config('qa.a',user_id::text,true)
 from public.space_members where space_id=current_setting('qa.space')::uuid
 order by joined_at limit 1;
select set_config('qa.b',user_id::text,true)
 from public.space_members where space_id=current_setting('qa.space')::uuid
 order by joined_at desc limit 1;
set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('qa.a'),true);
insert into public.notes(space_id,created_by,title,body,visibility)
 values(current_setting('qa.space')::uuid,current_setting('qa.a')::uuid,
 'R38 Shared QA note','','shared'),
 (current_setting('qa.space')::uuid,current_setting('qa.a')::uuid,
 'R38 Private QA note','','private');
insert into public.tasks(space_id,created_by,title,visibility)
 values(current_setting('qa.space')::uuid,current_setting('qa.a')::uuid,
 'R38 Shared QA task','shared'),
 (current_setting('qa.space')::uuid,current_setting('qa.a')::uuid,
 'R38 Private QA task','private');
select set_config('qa.shared_note',(select id::text from public.notes
 where title='R38 Shared QA note' limit 1),true);
select set_config('qa.private_note',(select id::text from public.notes
 where title='R38 Private QA note' limit 1),true);
select set_config('qa.shared_task',(select id::text from public.tasks
 where title='R38 Shared QA task' limit 1),true);
select set_config('qa.private_task',(select id::text from public.tasks
 where title='R38 Private QA task' limit 1),true);

insert into public.note_references(note_id,target_kind,target_id)
 values(current_setting('qa.shared_note')::uuid,'task',
  current_setting('qa.shared_task')::uuid),
 (current_setting('qa.private_note')::uuid,'task',
  current_setting('qa.private_task')::uuid);
do $qa$
declare denied boolean:=false;
begin
 begin
  insert into public.note_references(note_id,target_kind,target_id)
  values(current_setting('qa.shared_note')::uuid,'task',
    current_setting('qa.private_task')::uuid);
 exception when others then denied:=true;end;
 if not denied then raise exception 'Private task linked from shared note';end if;
 denied:=false;
 begin
  insert into public.note_references(note_id,target_kind,target_id)
  values(current_setting('qa.private_note')::uuid,'task',gen_random_uuid());
 exception when others then denied:=true;end;
 if not denied then raise exception 'Nonexistent target accepted';end if;
 denied:=false;
 begin
  insert into public.note_references(note_id,target_kind,target_id)
  values(current_setting('qa.shared_note')::uuid,'task',
    current_setting('qa.shared_task')::uuid);
 exception when unique_violation then denied:=true;end;
 if not denied then raise exception 'Duplicate link accepted';end if;
end $qa$;
select set_config('request.jwt.claim.sub',current_setting('qa.b'),true);
do $qa$
declare denied boolean:=false;
begin
 if (select count(*) from public.note_references)!=1 then
  raise exception 'Private note references leaked to other partner';end if;
 if exists(select 1 from public.note_references
  where note_id=current_setting('qa.private_note')::uuid) then
  raise exception 'Other partner sees private note link';end if;
 begin
  insert into public.note_references(note_id,target_kind,target_id)
  values(current_setting('qa.private_note')::uuid,'task',
    current_setting('qa.shared_task')::uuid);
 exception when others then denied:=true;end;
 if not denied then raise exception 'Other partner attached link to private note';end if;
end $qa$;
delete from public.note_references where
 note_id=current_setting('qa.shared_note')::uuid;
select 'PASS: R38 private links hidden, shared links visible, cross-scope denied, dedup and unlink' result;
rollback;