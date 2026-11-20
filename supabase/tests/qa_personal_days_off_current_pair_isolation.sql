-- QA two-scope days-off test. DML rolled back on all paths.
begin;
select set_config('qa.owner',(select user_id::text from public.space_members order by space_id,user_id limit 1),true);
select set_config('qa.space',(select space_id::text from public.space_members where user_id::text=current_setting('qa.owner') limit 1),true);
select set_config('qa.peer',(select user_id::text from public.space_members
 where space_id::text=current_setting('qa.space') and user_id::text<>current_setting('qa.owner') limit 1),true);
select set_config('qa.stranger',(select user_id::text from public.space_members
 where space_id::text<>current_setting('qa.space') limit 1),true);
select set_config('request.jwt.claim.sub',current_setting('qa.owner'),true);
set local role authenticated;
do $checks$
declare
 o uuid:=current_setting('qa.owner')::uuid;
 p uuid:=current_setting('qa.peer')::uuid;
 x uuid:=current_setting('qa.stranger')::uuid;
 s uuid:=current_setting('qa.space')::uuid;
 own_day uuid; shared_day uuid; n int;
begin
 if o is null or p is null or x is null or s is null then
   raise exception 'Paired and outsider QA users required';end if;
 insert into public.personal_days_off(private_space_id,user_id,off_date,label)
  values(o,o,date '2026-11-20','QA account day off')
  returning id into own_day;
 insert into public.personal_days_off(space_id,user_id,off_date,label)
  values(s,o,date '2026-11-21','QA shared day off')
  returning id into shared_day;
 select count(*) into n from public.personal_days_off where id=own_day and private_space_id=o and space_id is null;
 if n<>1 then raise exception 'Owner cannot read private day off';end if;
 perform set_config('request.jwt.claim.sub',p::text,true);
 select count(*) into n from public.personal_days_off where id=own_day;
 if n<>0 then raise exception 'Partner read private day off';end if;
 select count(*) into n from public.personal_days_off where id=shared_day;
 if n<>1 then raise exception 'Partner cannot read current-pair day off';end if;
 perform set_config('request.jwt.claim.sub',x::text,true);
 select count(*) into n from public.personal_days_off where id in (own_day,shared_day);
 if n<>0 then raise exception 'Unrelated user read another account/pair days off';end if;
 perform set_config('request.jwt.claim.sub',o::text,true);
 update public.personal_days_off set label='Changed by owner' where id=own_day;
 begin
   update public.personal_days_off set space_id=s,private_space_id=null where id=own_day;
   raise exception 'BUG: user could move private day off to couple';
 exception when others then
   if sqlerrm='BUG: user could move private day off to couple' then raise;end if;
 end;
 delete from public.personal_days_off where id=own_day;
 select count(*) into n from public.personal_days_off where id=own_day;
 if n<>0 then raise exception 'Owner cannot delete own private day off';end if;
end $checks$;
rollback;
select 'PASS days off account vs current couple owner/partner/outsider/immutability/delete; rolled back' result;
