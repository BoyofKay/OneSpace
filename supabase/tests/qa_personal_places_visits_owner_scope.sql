-- QA Places + Visits, rollback proof including child rows and partner isolation.
begin;
select set_config('qa.owner',(select user_id::text from public.space_members order by space_id,user_id limit 1),true);
select set_config('qa.space',(select space_id::text from public.space_members
 where user_id::text=current_setting('qa.owner') limit 1),true);
select set_config('qa.peer',(select user_id::text from public.space_members
 where space_id::text=current_setting('qa.space') and user_id::text<>current_setting('qa.owner') limit 1),true);
select set_config('qa.other',(select user_id::text from public.space_members
 where space_id::text<>current_setting('qa.space') limit 1),true);
select set_config('request.jwt.claim.sub',current_setting('qa.owner'),true);
set local role authenticated;
do $checks$
declare
 o uuid:=current_setting('qa.owner')::uuid;
 p uuid:=current_setting('qa.peer')::uuid;
 x uuid:=current_setting('qa.other')::uuid;
 s uuid:=current_setting('qa.space')::uuid;
 private_place uuid; shared_place uuid; private_visit uuid; shared_visit uuid;
 n int;
begin
 if o is null or p is null or x is null then raise exception 'Pair and unrelated QA user required';end if;
 insert into public.places(private_space_id,created_by,visibility,name)
 values(o,o,'private','QA private place rollback') returning id into private_place;
 insert into public.places(space_id,created_by,visibility,name)
 values(s,o,'shared','QA shared place rollback') returning id into shared_place;
 insert into public.place_visits(private_space_id,place_id,created_by,visited_on,caption)
 values(o,private_place,o,date '2026-11-20','Personal visit') returning id into private_visit;
 insert into public.place_visits(space_id,place_id,created_by,visited_on,caption)
 values(s,shared_place,o,date '2026-11-19','Shared visit') returning id into shared_visit;
 select count(*) into n from public.place_visits where id=private_visit and private_space_id=o and space_id is null;
 if n<>1 then raise exception 'Owner cannot read private visit';end if;
 perform set_config('request.jwt.claim.sub',p::text,true);
 select count(*) into n from public.places where id=private_place;
 if n<>0 then raise exception 'Partner sees private place';end if;
 select count(*) into n from public.place_visits where id=private_visit;
 if n<>0 then raise exception 'Partner sees private place visit';end if;
 select count(*) into n from public.places where id=shared_place;
 if n<>1 then raise exception 'Partner cannot read shared place';end if;
 select count(*) into n from public.place_visits where id=shared_visit;
 if n<>1 then raise exception 'Partner cannot read shared visit';end if;
 perform set_config('request.jwt.claim.sub',x::text,true);
 select count(*) into n from public.places where id in(private_place,shared_place);
 if n<>0 then raise exception 'Outsider sees scoped places';end if;
 select count(*) into n from public.place_visits where id in(private_visit,shared_visit);
 if n<>0 then raise exception 'Outsider sees scoped visits';end if;
 perform set_config('request.jwt.claim.sub',o::text,true);
 update public.places set notes='Updated by owner' where id=private_place;
 begin
  update public.places set visibility='shared' where id=private_place;
  raise exception 'BUG: could share account place by raw UPDATE';
 exception when others then
  if sqlerrm='BUG: could share account place by raw UPDATE' then raise;end if;
 end;
 begin
  update public.place_visits set place_id=shared_place where id=private_visit;
  raise exception 'BUG: could switch visit parent';
 exception when others then
  if sqlerrm='BUG: could switch visit parent' then raise;end if;
 end;
 begin
  insert into public.places(space_id,created_by,visibility,name)
  values(s,o,'private','QA stale couple-private place');
  raise exception 'BUG: stale couple-scoped private Place saved';
 exception when others then
  if sqlerrm='BUG: stale couple-scoped private Place saved' then raise;end if;
 end;
end $checks$;
rollback;
select 'PASS owner/pair/outsider Places and Visits; immutability; rolled back' result;
