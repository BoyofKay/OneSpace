-- QA personal feelings and current-couple shared entries; fully rolled back.
begin;
select set_config('qa.owner',(select user_id::text from public.space_members
 order by space_id,user_id limit 1),true);
select set_config('qa.space',(select space_id::text from public.space_members
 where user_id::text=current_setting('qa.owner') limit 1),true);
select set_config('qa.peer',(select user_id::text from public.space_members
 where space_id::text=current_setting('qa.space') and user_id::text<>current_setting('qa.owner')
 limit 1),true);
select set_config('qa.outside',(select user_id::text from public.space_members
 where space_id::text<>current_setting('qa.space') limit 1),true);
select set_config('request.jwt.claim.sub',current_setting('qa.owner'),true);
set local role authenticated;
do $check$
declare
 own uuid:=current_setting('qa.owner')::uuid;
 peer uuid:=current_setting('qa.peer')::uuid;
 outside uuid:=current_setting('qa.outside')::uuid;
 pair uuid:=current_setting('qa.space')::uuid;
 p_id uuid; s_id uuid; n int;
begin
 if own is null or peer is null or outside is null or pair is null
  then raise exception 'QA pair and outsider required';end if;
 insert into public.daily_checkins
  (private_space_id,created_by,visibility,checkin_date,mood,message,gratitude)
  values(own,own,'private',date '2026-11-20',3,'Private feeling rollback','')
  returning id into p_id;
 insert into public.daily_checkins
  (space_id,created_by,visibility,checkin_date,mood,message,gratitude)
  values(pair,own,'shared',date '2026-11-19',4,'Shared feeling rollback','')
  returning id into s_id;
 select count(*) into n from public.daily_checkins where id=p_id and private_space_id=own and space_id is null;
 if n<>1 then raise exception 'Owner cannot read own private feeling';end if;
 select count(*) into n from public.record_action_history where record_id=p_id and private_space_id=own;
 if n<>1 then raise exception 'Private feelings audit not visible to owner';end if;
 perform set_config('request.jwt.claim.sub',peer::text,true);
 select count(*) into n from public.daily_checkins where id=p_id;
 if n<>0 then raise exception 'Partner read private feeling';end if;
 select count(*) into n from public.record_action_history where record_id=p_id;
 if n<>0 then raise exception 'Partner read private feeling audit';end if;
 select count(*) into n from public.daily_checkins where id=s_id;
 if n<>1 then raise exception 'Partner cannot read shared feeling';end if;
 perform set_config('request.jwt.claim.sub',outside::text,true);
 select count(*) into n from public.daily_checkins where id in (p_id,s_id);
 if n<>0 then raise exception 'Outsider read personal/shared feeling';end if;
 perform set_config('request.jwt.claim.sub',own::text,true);
 update public.daily_checkins set message='Edited by owner' where id=p_id;
 begin
  update public.daily_checkins set visibility='shared' where id=p_id;
  raise exception 'BUG: private feeling changed visibility';
 exception when others then
  if sqlerrm='BUG: private feeling changed visibility' then raise;end if;
 end;
 begin
  insert into public.daily_checkins(space_id,created_by,visibility,checkin_date,mood,message)
   values(pair,own,'private',date '2026-11-18',3,'Stale client write');
  raise exception 'BUG: stale private couple-scoped checkin allowed';
 exception when others then
  if sqlerrm='BUG: stale private couple-scoped checkin allowed' then raise;end if;
 end;
end $check$;
rollback;
select 'PASS personal feelings owner/peer/outsider/audit and stale-client guard; rolled back' as result;
