-- QA Goals privacy regression, all writes rolled back.
begin;
select set_config('qa.owner',(select user_id::text from public.space_members order by space_id,user_id limit 1),true);
select set_config('qa.space',(select space_id::text from public.space_members where user_id::text=current_setting('qa.owner') limit 1),true);
select set_config('qa.peer',(select user_id::text from public.space_members
 where space_id::text=current_setting('qa.space') and user_id::text<>current_setting('qa.owner') limit 1),true);
select set_config('qa.stranger',(select user_id::text from public.space_members where space_id::text<>current_setting('qa.space') limit 1),true);
select set_config('request.jwt.claim.sub',current_setting('qa.owner'),true);
set local role authenticated;
do $checks$
declare o uuid:=current_setting('qa.owner')::uuid;
 p uuid:=current_setting('qa.peer')::uuid; x uuid:=current_setting('qa.stranger')::uuid;
 s uuid:=current_setting('qa.space')::uuid; pr uuid; sh uuid; n int;
begin
 if o is null or p is null or x is null then raise exception 'Need three QA identities';end if;
 insert into public.goals(private_space_id,created_by,visibility,title,description)
 values(o,o,'private','QA private goal rollback','Private progress')
 returning id into pr;
 insert into public.goals(space_id,created_by,visibility,title,description)
 values(s,o,'shared','QA pair goal rollback','Shared progress')
 returning id into sh;
 select count(*) into n from public.record_action_history where record_id=pr and private_space_id=o;
 if n<>1 then raise exception 'Owner cannot read personal goal audit';end if;
 perform set_config('request.jwt.claim.sub',p::text,true);
 select count(*) into n from public.goals where id=pr;
 if n<>0 then raise exception 'Partner sees private goal';end if;
 select count(*) into n from public.goals where id=sh;
 if n<>1 then raise exception 'Partner cannot see shared goal';end if;
 select count(*) into n from public.record_action_history where record_id=pr;
 if n<>0 then raise exception 'Partner sees private goal history';end if;
 perform set_config('request.jwt.claim.sub',x::text,true);
 select count(*) into n from public.goals where id in (pr,sh);
 if n<>0 then raise exception 'Outsider sees scoped goals';end if;
 perform set_config('request.jwt.claim.sub',o::text,true);
 update public.goals set progress=20 where id=pr;
 begin
  update public.goals set visibility='shared' where id=pr;
  raise exception 'BUG: personal goal visibility changed';
 exception when others then
  if sqlerrm='BUG: personal goal visibility changed' then raise; end if;
 end;
 begin
  insert into public.goals(space_id,created_by,visibility,title,description)
   values(s,o,'private','Stale goal rollback','Should fail');
  raise exception 'BUG: stale couple-private goal created';
 exception when others then
  if sqlerrm='BUG: stale couple-private goal created' then raise;end if;
 end;
end $checks$;
rollback;
select 'PASS Goals owner/partner/outsider/audit/write guard; rolled back' result;
