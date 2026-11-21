-- QA rollback-only checks for 0313.
do $t$
declare
  a uuid:='db1ac811-6fb0-4f31-8e6c-4e37b5d3a70d';
  b uuid:='77b679f8-1a70-4347-a95e-9a39d3ea6977';
  c uuid:='937e362d-6457-4fe2-b8cd-abad7157a015';
  couple uuid:='db24ba25-8f22-4565-85df-b1e9edab8e00';
  sel uuid; sb uuid; n int; failed boolean; r record;
begin
  delete from public.memories where memory_type='daily_selfie' and memory_date=current_date and created_by in (a,b);
  delete from public.account_birthdays where user_id in (a,b,c);
  delete from public.account_holiday_countries where user_id in (a,b,c);
  update public.profiles set partner_label='Love', partner_labels='{Habibi}' where id in (a,b);

  -- 1. A private daily selfie; a second one the same day is refused.
  perform set_config('request.jwt.claims',json_build_object('sub',a,'role','authenticated')::text,true);
  set local role authenticated;
  insert into public.memories(private_space_id,created_by,visibility,title,body,memory_date,memory_type,photo_layout)
   values(a,a,'private','Selfie','',current_date,'daily_selfie','polaroid') returning id into sel;
  failed:=false;
  begin insert into public.memories(private_space_id,created_by,visibility,title,body,memory_date,memory_type,photo_layout)
    values(a,a,'private','Selfie 2','',current_date,'daily_selfie','polaroid');
  exception when unique_violation then failed:=true; end;
  if not failed then raise exception 'FAIL 1: two daily selfies on one day'; end if;

  -- 2. Scrapbook invite withdraw.
  sb:=public.create_scrapbook(couple,'Our book','polaroid_letters','shared',current_date);
  perform public.invite_scrapbook_partner(sb);
  perform public.revoke_scrapbook_invite(sb);
  reset role;
  if exists(select 1 from public.scrapbook_invites where memory_id=sb) then
    raise exception 'FAIL 2: invitation not withdrawn'; end if;
  if exists(select 1 from public.space_notifications where kind='scrapbook_invite' and object_id=sb) then
    raise exception 'FAIL 2b: invitation notification left behind'; end if;

  -- 3. Birthday sharing: hidden by default, year only when chosen.
  perform set_config('request.jwt.claims',json_build_object('sub',a,'role','authenticated')::text,true);
  set local role authenticated;
  insert into public.account_birthdays(user_id,month,day,year) values(a,3,14,1990);
  insert into public.account_holiday_countries(user_id,country_code) values(a,'JP');
  reset role;
  perform set_config('request.jwt.claims',json_build_object('sub',b,'role','authenticated')::text,true);
  set local role authenticated;
  select count(*) into n from public.partner_birthday();
  if n<>0 then raise exception 'FAIL 3: birthday visible before sharing'; end if;
  select count(*) into n from public.account_birthdays where user_id=a;
  if n<>0 then raise exception 'FAIL 3b: partner reads the birthday row directly'; end if;
  select count(*) into n from public.account_holiday_countries where user_id=a and country_code='JP';
  if n<>1 then raise exception 'FAIL 3c: partner cannot see holiday countries'; end if;
  reset role;
  perform set_config('request.jwt.claims',json_build_object('sub',a,'role','authenticated')::text,true);
  set local role authenticated;
  update public.account_birthdays set share_with_partner=true where user_id=a;
  reset role;
  perform set_config('request.jwt.claims',json_build_object('sub',b,'role','authenticated')::text,true);
  set local role authenticated;
  select * into r from public.partner_birthday();
  if r.person_id is distinct from a or r.month<>3 or r.day<>14 or r.year is not null then
    raise exception 'FAIL 4: shared birthday wrong (year must stay hidden)'; end if;
  reset role;
  perform set_config('request.jwt.claims',json_build_object('sub',c,'role','authenticated')::text,true);
  set local role authenticated;
  select count(*) into n from public.partner_birthday();
  if n<>0 then raise exception 'FAIL 5: outsider sees a birthday'; end if;
  select count(*) into n from public.account_holiday_countries where user_id=a;
  if n<>0 then raise exception 'FAIL 5b: outsider sees holiday countries'; end if;
  reset role;

  -- 6. Pairing ends: birthday sharing and partner names reset; living
  --    arrangement cannot change in a one-person space.
  delete from public.space_members where space_id=couple and user_id=b;
  if exists(select 1 from public.account_birthdays where user_id=a and share_with_partner) then
    raise exception 'FAIL 6: birthday sharing survived the pairing change'; end if;
  if exists(select 1 from public.profiles where id in (a,b) and (partner_label is not null or cardinality(partner_labels)>0)) then
    raise exception 'FAIL 7: preferred partner names survived separation'; end if;
  perform set_config('request.jwt.claims',json_build_object('sub',a,'role','authenticated')::text,true);
  set local role authenticated;
  failed:=false;
  begin update public.spaces set relationship_mode='living_together' where id=couple;
  exception when others then failed:=true; end;
  if not failed then raise exception 'FAIL 8: solo space changed living arrangement'; end if;
  reset role;
  raise notice 'ALL 0313 CHECKS PASSED';
end $t$;
