-- QA: authenticated, rollback-only tests. Never leave user content or
-- alter a real membership after execution.
begin;
select set_config('qa.owner',(select sm.user_id::text from public.space_members sm
 order by sm.user_id limit 1),true);
select set_config('qa.partner',(select sm.user_id::text from public.space_members sm
 where sm.space_id=(select space_id from public.space_members
  where user_id=current_setting('qa.owner')::uuid limit 1)
 and sm.user_id::text<>current_setting('qa.owner') limit 1),true);
select set_config('qa.stranger',(select sm.user_id::text from public.space_members sm
 where sm.space_id<>(select space_id from public.space_members
  where user_id=current_setting('qa.owner')::uuid limit 1)
 limit 1),true);
select set_config('request.jwt.claim.sub',current_setting('qa.owner'),true);
set local role authenticated;
do $qa$
declare o uuid:=current_setting('qa.owner')::uuid;
 b uuid:=current_setting('qa.partner')::uuid;
 outsider uuid:=current_setting('qa.stranger')::uuid;
 a uuid; m uuid;c uuid;n int;res record;
begin
 insert into public.activities(private_space_id,created_by,title,body,visibility)
 values(o,o,'Rollback personal Activity','Confidential Activity details','private') returning id into a;
 insert into public.activity_components(activity_id,created_by,kind,label,payload)
 values(a,o,'step','Safe personal step','{"value":"","status":"open"}'::jsonb)
 returning id into c;
 insert into public.activity_comments(activity_id,author_id,body)
 values(a,o,'Private Activity comment');
 insert into public.memories(private_space_id,created_by,title,body,memory_date,visibility)
 values(o,o,'Rollback personal Memory','Confidential journal',current_date,'private') returning id into m;
 select count(*) into n from public.record_action_history h
 where h.record_id in(a,m) and h.private_space_id=o;
 if n<>2 then raise exception 'Missing Activity and Memory audit';end if;
 select * into res from public.record_activity_decision(a,'postponed',null,'Paused');
 if res.activity_id<>a then raise exception 'Personal decision failure';end if;
 perform set_config('request.jwt.claim.sub',b::text,true);
 select count(*) into n from public.activities where id=a;
 if n<>0 then raise exception 'Partner can see private Activity';end if;
 select count(*) into n from public.memories where id=m;
 if n<>0 then raise exception 'Partner can see private Memory';end if;
 select count(*) into n from public.activity_comments where activity_id=a;
 if n<>0 then raise exception 'Partner can see private Activity conversation';end if;
 select count(*) into n from public.activity_decisions where activity_id=a;
 if n<>0 then raise exception 'Partner can see private Activity decisions';end if;
 select count(*) into n from public.record_action_history where record_id in(a,m);
 if n<>0 then raise exception 'Partner can see private object audit';end if;
 perform set_config('request.jwt.claim.sub',outsider::text,true);
 select count(*) into n from public.activity_components where activity_id=a;
 if n<>0 then raise exception 'Outsider can see private Activity components';end if;
 perform set_config('request.jwt.claim.sub',o::text,true);
 update public.activities set body='Owner edited private Activity' where id=a;
 update public.memories set body='Owner edited private Memory' where id=m;
 begin
  update public.activities set created_by=b where id=a;
  raise exception 'BUG: private Activity owner changed';
 exception when others then
  if sqlerrm='BUG: private Activity owner changed' then raise; end if;
 end;
 begin
  insert into public.activity_components(activity_id,created_by,kind,label,payload)
  values(a,o,'image','Forbidden media','{}'::jsonb);
  raise exception 'BUG: unsafe private Activity media permitted';
 exception when others then
  if sqlerrm='BUG: unsafe private Activity media permitted' then raise;end if;
 end;
 begin
  update public.memories set memory_type='daily_selfie' where id=m;
  raise exception 'BUG: unsafe personal media permitted';
 exception when others then
  if sqlerrm='BUG: unsafe personal media permitted' then raise;end if;
 end;
 begin
  update public.activity_components set activity_id=gen_random_uuid() where id=c;
  raise exception 'BUG: component moved to another parent';
 exception when others then
  if sqlerrm='BUG: component moved to another parent' then raise;end if;
 end;
end $qa$;
rollback;
