-- QA regression for Saved Contacts (#129) and 0307: direct contact cards and
-- contacts held inside an Activity, in both personal and couple scope.
-- Run inside BEGIN ... ROLLBACK only. A, B: couple db24ba25-…; C: outsider.
-- Each step raises on failure, so a clean run means every check passed.
do $t$
declare
  a uuid:='db1ac811-6fb0-4f31-8e6c-4e37b5d3a70d';
  b uuid:='77b679f8-1a70-4347-a95e-9a39d3ea6977';
  c uuid:='937e362d-6457-4fe2-b8cd-abad7157a015';
  couple uuid:='db24ba25-8f22-4565-85df-b1e9edab8e00';
  mine uuid; ours uuid; act_mine uuid; act_ours uuid;
  comp_mine uuid; comp_ours uuid; n int; failed boolean;
  card jsonb:=jsonb_build_object('person','Dr Lina','phone','+966500000000');
begin
  perform set_config('request.jwt.claims',json_build_object('sub',a,'role','authenticated')::text,true);
  set local role authenticated;
  -- Direct cards.
  insert into public.saved_contacts(private_space_id,created_by,visibility,label,payload)
   values(a,a,'private','My dentist',card) returning id into mine;
  insert into public.saved_contacts(space_id,created_by,visibility,label,payload)
   values(couple,a,'shared','Our plumber',card) returning id into ours;
  select count(*) into n from public.saved_contacts where id in (mine,ours);
  if n<>2 then raise exception 'FAIL 1: owner cannot see own direct cards'; end if;
  update public.saved_contacts set label='My dentist (new)' where id=mine;
  get diagnostics n=row_count;
  if n<>1 then raise exception 'FAIL 2: owner cannot edit personal card'; end if;
  failed:=false;
  begin update public.saved_contacts set visibility='shared' where id=mine;
  exception when others then failed:=true; end;
  if not failed then raise exception 'FAIL 3: personal card made shared by edit'; end if;
  failed:=false;
  begin update public.saved_contacts set private_space_id=null,space_id=couple where id=mine;
  exception when others then failed:=true; end;
  if not failed then raise exception 'FAIL 4: personal card moved into couple'; end if;
  failed:=false;
  begin insert into public.saved_contacts(private_space_id,created_by,visibility,label,payload)
    values(b,a,'private','Planted',card);
  exception when others then failed:=true; end;
  if not failed then raise exception 'FAIL 5: card planted in partner personal space'; end if;

  -- Activity-linked contact and link cards.
  insert into public.activities(private_space_id,created_by,visibility,title)
   values(a,a,'private','Find a clinic') returning id into act_mine;
  insert into public.activities(space_id,created_by,visibility,title)
   values(couple,a,'shared','Fix the sink') returning id into act_ours;
  insert into public.activity_components(activity_id,created_by,kind,label,payload)
   values(act_mine,a,'contact','Clinic desk',card) returning id into comp_mine;
  if comp_mine is null then raise exception 'FAIL 6: contact refused on personal Activity'; end if;
  insert into public.activity_components(activity_id,created_by,kind,label,payload)
   values(act_mine,a,'link','Clinic site',jsonb_build_object('value','https://example.com'));
  insert into public.activity_components(activity_id,created_by,kind,label,payload)
   values(act_ours,a,'contact','Plumber desk',card) returning id into comp_ours;
  update public.activity_components set label='Clinic front desk' where id=comp_mine;
  get diagnostics n=row_count;
  if n<>1 then raise exception 'FAIL 7: owner cannot edit personal Activity contact'; end if;
  reset role;

  -- Partner B: sees the couple's cards only.
  perform set_config('request.jwt.claims',json_build_object('sub',b,'role','authenticated')::text,true);
  set local role authenticated;
  select count(*) into n from public.saved_contacts where id=mine;
  if n<>0 then raise exception 'FAIL 8: partner sees personal direct card'; end if;
  select count(*) into n from public.saved_contacts where id=ours;
  if n<>1 then raise exception 'FAIL 9: partner cannot see shared direct card'; end if;
  update public.saved_contacts set label='Hijack' where id=mine;
  get diagnostics n=row_count;
  if n<>0 then raise exception 'FAIL 10: partner edited personal direct card'; end if;
  select count(*) into n from public.activity_components where activity_id=act_mine;
  if n<>0 then raise exception 'FAIL 11: partner sees personal Activity contacts'; end if;
  select count(*) into n from public.activity_components where id=comp_ours;
  if n<>1 then raise exception 'FAIL 12: partner cannot see shared Activity contact'; end if;
  update public.activity_components set label='Hijack' where id=comp_mine;
  get diagnostics n=row_count;
  if n<>0 then raise exception 'FAIL 13: partner edited personal Activity contact'; end if;
  failed:=false;
  begin insert into public.activity_components(activity_id,created_by,kind,label,payload)
    values(act_mine,b,'contact','Planted',card);
  exception when others then failed:=true; end;
  if not failed then raise exception 'FAIL 14: partner added contact to personal Activity'; end if;
  reset role;

  -- Outsider C: sees nothing and cannot write into the couple.
  perform set_config('request.jwt.claims',json_build_object('sub',c,'role','authenticated')::text,true);
  set local role authenticated;
  select count(*) into n from public.saved_contacts where id in (mine,ours);
  if n<>0 then raise exception 'FAIL 15: outsider sees direct cards'; end if;
  select count(*) into n from public.activity_components where id in (comp_mine,comp_ours);
  if n<>0 then raise exception 'FAIL 16: outsider sees Activity contacts'; end if;
  failed:=false;
  begin insert into public.saved_contacts(space_id,created_by,visibility,label,payload)
    values(couple,c,'shared','Intrude',card);
  exception when others then failed:=true; end;
  if not failed then raise exception 'FAIL 17: outsider added card to another couple'; end if;
  reset role;
  raise notice 'PASS: 17 saved contact checks';
end $t$;
