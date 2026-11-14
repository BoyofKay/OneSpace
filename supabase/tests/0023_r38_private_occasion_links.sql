-- R38 rollback-only private surprise check. No user data persists.
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
insert into public.notes(space_id,created_by,title,visibility)
 values (current_setting('qa.space')::uuid,current_setting('qa.a')::uuid,
 'R38 safe shared note','shared'),
 (current_setting('qa.space')::uuid,current_setting('qa.a')::uuid,
 'R38 private surprise note','private');
insert into public.occasion_plans(space_id,title,occasion_on,visibility)
 values(current_setting('qa.space')::uuid,'R38 private occasion',date '2026-12-25','private');
select set_config('qa.shared',(select id::text from public.notes
 where title='R38 safe shared note' limit 1),true);
select set_config('qa.private',(select id::text from public.notes
 where title='R38 private surprise note' limit 1),true);
select set_config('qa.surprise',(select id::text from public.occasion_plans
 where title='R38 private occasion' limit 1),true);
do $qa$
declare denied boolean:=false;
begin
 begin
  insert into public.note_references(note_id,target_kind,target_id)
  values(current_setting('qa.shared')::uuid,'occasion',
   current_setting('qa.surprise')::uuid);
 exception when others then denied:=true;end;
 if not denied then raise exception 'Private surprise leaked in shared note';end if;
end $qa$;
insert into public.note_references(note_id,target_kind,target_id)
 values(current_setting('qa.private')::uuid,'occasion',
  current_setting('qa.surprise')::uuid);
select set_config('request.jwt.claim.sub',current_setting('qa.b'),true);
do $qa$
begin
 if exists (select 1 from public.note_references where
   target_id=current_setting('qa.surprise')::uuid) then
  raise exception 'Other partner saw private surprise reference';end if;
 if exists (select 1 from public.occasion_plans where
   id=current_setting('qa.surprise')::uuid) then
  raise exception 'Other partner saw private surprise source';end if;
end $qa$;
select 'PASS: R38 private occasions cannot be linked or exposed by shared notes' result;
rollback;