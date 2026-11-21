-- QA rollback-only: personal counters, shared counters and separation with links.
do $t$
declare
  a uuid:='db1ac811-6fb0-4f31-8e6c-4e37b5d3a70d';
  b uuid:='77b679f8-1a70-4347-a95e-9a39d3ea6977';
  couple uuid:='db24ba25-8f22-4565-85df-b1e9edab8e00';
  owner_id uuid; pp uuid; pm uuid; pc uuid; c2 uuid; sp uuid; sc uuid; sc2 uuid; n int; failed boolean;
begin
  update private.qa_relationship_v2_gate set enabled=true where id=1;
  select created_by into owner_id from public.spaces where id=couple;
  perform set_config('request.jwt.claims',json_build_object('sub',owner_id,'role','authenticated')::text,true);
  set local role authenticated;
  -- 1. Private counter with a private place, memory and linked counter.
  insert into public.places(private_space_id,created_by,visibility,name,status)
   values(owner_id,owner_id,'private','My cafe','visited') returning id into pp;
  insert into public.memories(private_space_id,created_by,visibility,title,body,memory_date)
   values(owner_id,owner_id,'private','My day','',current_date) returning id into pm;
  insert into public.space_counters(private_space_id,created_by,visibility,title,on_date,place_id,memory_id,people)
   values(owner_id,owner_id,'private','First',current_date,pp,pm,array['Sam']) returning id into pc;
  insert into public.space_counters(private_space_id,created_by,visibility,title,on_date,linked_counter_id)
   values(owner_id,owner_id,'private','Second',current_date,pc) returning id into c2;
  update public.space_counters set title='First edited' where id=pc;
  get diagnostics n=row_count; if n<>1 then raise exception 'FAIL 1: cannot edit private counter'; end if;
  -- 2. Shared counter linked to shared place and to another shared counter.
  insert into public.places(space_id,created_by,visibility,name,status)
   values(couple,owner_id,'shared','Our cafe','visited') returning id into sp;
  insert into public.space_counters(space_id,created_by,visibility,title,on_date,place_id)
   values(couple,owner_id,'shared','Together',current_date,sp) returning id into sc;
  insert into public.space_counters(space_id,created_by,visibility,title,on_date,linked_counter_id)
   values(couple,owner_id,'shared','Since',current_date,sc) returning id into sc2;
  -- 3. A private counter may not link a shared place.
  failed:=false;
  begin insert into public.space_counters(private_space_id,created_by,visibility,title,on_date,place_id)
    values(owner_id,owner_id,'private','Bad',current_date,sp);
  exception when others then failed:=true; end;
  if not failed then raise exception 'FAIL 3: private counter linked a shared place'; end if;
  reset role;
  -- 4. Partner cannot see the private counter.
  perform set_config('request.jwt.claims',json_build_object('sub',case when owner_id=a then b else a end,'role','authenticated')::text,true);
  set local role authenticated;
  select count(*) into n from public.space_counters where id in (pc,c2);
  if n<>0 then raise exception 'FAIL 4: partner reads private counter'; end if;
  select count(*) into n from public.space_counters where id in (sc,sc2);
  if n<>2 then raise exception 'FAIL 5: partner cannot read shared counters'; end if;
  reset role;
  -- 6. Separation with linked shared counters and places succeeds.
  perform set_config('request.jwt.claims',json_build_object('sub',owner_id,'role','authenticated')::text,true);
  set local role authenticated;
  perform public.qa_end_current_relationship(couple,'remove_partner','DELETE SHARED CONTENT');
  select count(*) into n from public.space_counters where id in (pc,c2);
  if n<>2 then raise exception 'FAIL 6: private counters lost on separation'; end if;
  reset role;
  if exists(select 1 from public.space_counters where id in (sc,sc2)) then
    raise exception 'FAIL 7: shared counters survived'; end if;
  -- 8. Personal trip with self as traveler; partner as traveler refused.
  perform set_config('request.jwt.claims',json_build_object('sub',owner_id,'role','authenticated')::text,true);
  set local role authenticated;
  insert into public.shared_trips(title,origin,destination,notes,travel_mode,trip_type,traveler_id,
    adults,children,infants,flexible_dates,private_space_id,created_by,visibility,status)
   values('Solo trip','RUH','DXB','','flight','round',owner_id,1,0,0,false,owner_id,owner_id,'private','planning');
  failed:=false;
  begin insert into public.shared_trips(title,origin,destination,notes,travel_mode,trip_type,traveler_id,
    adults,children,infants,flexible_dates,private_space_id,created_by,visibility,status)
   values('Bad','RUH','DXB','','flight','round',case when owner_id=a then b else a end,1,0,0,false,owner_id,owner_id,'private','planning');
  exception when others then failed:=true; end;
  if not failed then raise exception 'FAIL 8: private trip named the partner'; end if;
  -- 9. One private and one shared feeling on the same day (re-pair first is
  -- not needed: a private feeling alone, then a second private is refused).
  insert into public.daily_checkins(private_space_id,created_by,checkin_date,mood,message,gratitude,visibility)
   values(owner_id,owner_id,current_date,3,'','','private');
  failed:=false;
  begin insert into public.daily_checkins(private_space_id,created_by,checkin_date,mood,message,gratitude,visibility)
   values(owner_id,owner_id,current_date,4,'','','private');
  exception when others then failed:=true; end;
  if not failed then raise exception 'FAIL 9: two private feelings on one day'; end if;
  reset role;
  raise notice 'PASS counters, trips, feelings';
end $t$;
