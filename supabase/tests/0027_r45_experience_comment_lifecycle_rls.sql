-- R45: rollback-only RLS/authenticated actor lifecycle; no fixture persists.
begin;
select set_config('qa.space',space_id::text,true)
 from public.space_members group by space_id having count(*)=2 limit 1;
select set_config('qa.a',user_id::text,true)
 from public.space_members where space_id=current_setting('qa.space')::uuid
 order by joined_at limit 1;
select set_config('qa.b',user_id::text,true)
 from public.space_members where space_id=current_setting('qa.space')::uuid
 order by joined_at desc limit 1;
-- Fixtures inserted only by migration owner; actual EDIT and all SELECT
-- assertions below run as authenticated, using each member's JWT identity.
select set_config('request.jwt.claim.sub',current_setting('qa.a'),true);
insert into public.shared_experiences(space_id,created_by,category,title)
 values(current_setting('qa.space')::uuid,current_setting('qa.a')::uuid,
 'movie','R45 audit QA');
select set_config('qa.experience',(select id::text from public.shared_experiences
 where title='R45 audit QA' and space_id=current_setting('qa.space')::uuid
 order by created_at desc limit 1),true);
insert into public.shared_experience_comments(experience_id,created_by,body)
 values(current_setting('qa.experience')::uuid,current_setting('qa.a')::uuid,
 'R45 original text');
select set_config('qa.comment',(select id::text from public.shared_experience_comments
 where experience_id=current_setting('qa.experience')::uuid
 order by created_at desc limit 1),true);
set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('qa.b'),true);
do $qa$
declare n integer;
begin
 select count(*) into n from public.shared_experience_comments
  where id=current_setting('qa.comment')::uuid;
 if n<>1 then raise exception 'Partner cannot view active comment';end if;
 update public.shared_experience_comments set body='Unauthorized edit'
  where id=current_setting('qa.comment')::uuid;
 get diagnostics n=row_count;
 if n<>0 then raise exception 'Partner could edit an author-owned comment';end if;
end $qa$;
select set_config('request.jwt.claim.sub',current_setting('qa.a'),true);
update public.shared_experience_comments set body='R45 edited author text'
 where id=current_setting('qa.comment')::uuid;
update public.shared_experience_comments set archived_at=now()
 where id=current_setting('qa.comment')::uuid;
select set_config('request.jwt.claim.sub',current_setting('qa.b'),true);
do $qa$
begin
 if exists(select 1 from public.shared_experience_comments
  where id=current_setting('qa.comment')::uuid)then
  raise exception 'Retracted comment leaked to partner';end if;
 if exists(select 1 from public.record_action_history
  where record_kind='experience_comment' and
   record_id=current_setting('qa.comment')::uuid)then
  raise exception 'Retracted comment history leaked to partner';end if;
end $qa$;
select set_config('request.jwt.claim.sub',current_setting('qa.a'),true);
do $qa$
declare n integer;
begin
 select count(*) into n from public.record_action_history
 where record_kind='experience_comment' and
  record_id=current_setting('qa.comment')::uuid
  and action in ('created','edited','archived');
 if n<>3 then raise exception 'Missing created/edited/archived history: %',n;end if;
 if exists(select 1 from public.record_action_history
  where record_id=current_setting('qa.comment')::uuid and
  ('R45 edited author text'=any(changed_fields) or
   'R45 original text'=any(changed_fields)))then
  raise exception 'Sensitive comment body leaked into field audit';end if;
end $qa$;
update public.shared_experience_comments set archived_at=null
 where id=current_setting('qa.comment')::uuid;
select set_config('request.jwt.claim.sub',current_setting('qa.b'),true);
do $qa$
begin
 if not exists(select 1 from public.shared_experience_comments
  where id=current_setting('qa.comment')::uuid and body='R45 edited author text')then
  raise exception 'Restored comment not readable to partner';end if;
 if not exists(select 1 from public.record_action_history
  where record_id=current_setting('qa.comment')::uuid and action='restored')then
  raise exception 'Restore not present in audit';end if;
end $qa$;
select 'PASS: R45 comment author/edit/retract/restore and visibility/audit' result;
rollback;
