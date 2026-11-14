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
insert into public.shared_trips(space_id,title,origin,destination,visibility,status)
 values(current_setting('qa.space')::uuid,'QA private flight R27','Riyadh','Philadelphia','private','planning'),
 (current_setting('qa.space')::uuid,'QA shared flight R27','Riyadh','Philadelphia','shared','planning');
select set_config('qa.private',(select id::text from public.shared_trips where title='QA private flight R27'),true);
select set_config('qa.shared',(select id::text from public.shared_trips where title='QA shared flight R27'),true);
insert into public.trip_flight_options(trip_id,title,provider,price,currency,preference_score)
 values(current_setting('qa.private')::uuid,'QA-PVT','Test airline',100,'USD',4),
 (current_setting('qa.shared')::uuid,'QA-SHARED','Test airline',250,'USD',5);
select set_config('request.jwt.claim.sub',current_setting('qa.b'),true);
do $t$
declare denied boolean:=false;
begin
 if exists(select 1 from public.trip_flight_options where title='QA-PVT')
 then raise exception 'Private airfare candidate exposed to partner';end if;
 if (select count(*) from public.trip_flight_options where title='QA-SHARED')<>1
 then raise exception 'Shared airfare not visible';end if;
 update public.trip_flight_options set preference_score=3 where title='QA-SHARED';
 if not found then raise exception 'Partner cannot edit shared candidate';end if;
 begin
  insert into public.trip_flight_options(trip_id,title)
  values(current_setting('qa.private')::uuid,'FORGED');
 exception when others then denied:=true;end;
 if not denied then raise exception 'Partner could add to private itinerary';end if;
end $t$;
select 'PASS: R27 private/shared airfare candidate RLS and partner collaboration' result;
rollback;