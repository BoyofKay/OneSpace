-- R40 who/what/when and privacy regression: entirely rolled back.
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
 'R40 private audit test','Secret sample','private'),
 (current_setting('qa.space')::uuid,current_setting('qa.a')::uuid,
 'R40 shared audit test','Shared sample','shared');
select set_config('qa.private',(select id::text from public.notes
 where title='R40 private audit test' limit 1),true);
select set_config('qa.shared',(select id::text from public.notes
 where title='R40 shared audit test' limit 1),true);
update public.notes set title='R40 changed title'
 where id=current_setting('qa.private')::uuid;
update public.notes set archived_at=now()
 where id=current_setting('qa.private')::uuid;
update public.notes set archived_at=null
 where id=current_setting('qa.private')::uuid;
do $qa$
declare count_all int; count_created int; count_edited int;
begin
 select count(*) into count_all from public.record_action_history
 where record_kind='note' and record_id=current_setting('qa.private')::uuid;
 if count_all<>4 then raise exception 'Expected four events, got %',count_all;end if;
 if not exists(select 1 from public.record_action_history where
 record_id=current_setting('qa.private')::uuid and
 action='edited' and 'title'=any(changed_fields) and
 actor_id=current_setting('qa.a')::uuid and happened_at is not null)then
 raise exception 'Missing trustworthy actor/time/title event';end if;
 if not exists(select 1 from public.record_action_history where
 record_id=current_setting('qa.private')::uuid and
 action='archived')then raise exception 'Missing archive event';end if;
 if not exists(select 1 from public.record_action_history where
 record_id=current_setting('qa.private')::uuid and
 action='restored')then raise exception 'Missing restore event';end if;
end $qa$;
select set_config('request.jwt.claim.sub',current_setting('qa.b'),true);
do $qa$
begin
 if exists(select 1 from public.record_action_history
  where record_id=current_setting('qa.private')::uuid) then
  raise exception 'Private event history leaked to partner';end if;
 if not exists(select 1 from public.record_action_history
  where record_id=current_setting('qa.shared')::uuid and action='created')then
  raise exception 'Shared history missing for partner';end if;
end $qa$;
select 'PASS: audit create/edit/archive/restore, field changes, authentic actor/time and RLS' result;
rollback;