-- QA rollback-only checks for 0314.
do $t$
declare
  a uuid:='db1ac811-6fb0-4f31-8e6c-4e37b5d3a70d';
  b uuid:='77b679f8-1a70-4347-a95e-9a39d3ea6977';
  c uuid:='937e362d-6457-4fe2-b8cd-abad7157a015';
  couple uuid:='db24ba25-8f22-4565-85df-b1e9edab8e00';
  e1 uuid; e2 uuid; sb uuid; owner_id uuid; other uuid; failed boolean; n int;
begin
  select created_by into owner_id from public.spaces where id=couple;
  other:=case when owner_id=a then b else a end;
  -- 1. A private event for my partner, and for both of us.
  perform set_config('request.jwt.claims',json_build_object('sub',a,'role','authenticated')::text,true);
  set local role authenticated;
  insert into public.space_events(private_space_id,created_by,visibility,title,details,event_date,kind,for_user_id)
   values(a,a,'private','Surprise for B','',current_date,'event',b) returning id into e1;
  insert into public.space_events(private_space_id,created_by,visibility,title,details,event_date,kind,for_user_id)
   values(a,a,'private','Plan for us','',current_date,'event',null) returning id into e2;
  select count(*) into n from public.space_events where id in (e1,e2);
  if n<>2 then raise exception 'FAIL 1: owner cannot read private events for partner/both'; end if;
  failed:=false;
  begin insert into public.space_events(private_space_id,created_by,visibility,title,details,event_date,kind,for_user_id)
    values(a,a,'private','For C','',current_date,'event',c);
  exception when others then failed:=true; end;
  if not failed then raise exception 'FAIL 2: private event for a non-partner accepted'; end if;
  reset role;
  -- 3. Partner never sees my private event, even when it is for them.
  perform set_config('request.jwt.claims',json_build_object('sub',b,'role','authenticated')::text,true);
  set local role authenticated;
  select count(*) into n from public.space_events where id in (e1,e2);
  if n<>0 then raise exception 'FAIL 3: partner sees a private event'; end if;
  reset role;

  -- 4. Shared scrapbook: the partner edits pages without any invitation.
  perform set_config('request.jwt.claims',json_build_object('sub',owner_id,'role','authenticated')::text,true);
  set local role authenticated;
  sb:=public.create_scrapbook(couple,'Our book','polaroid_letters','shared',current_date);
  reset role;
  perform set_config('request.jwt.claims',json_build_object('sub',other,'role','authenticated')::text,true);
  set local role authenticated;
  update public.scrapbook_pages set title='Partner edit' where memory_id=sb;
  get diagnostics n=row_count;
  if n<>1 then raise exception 'FAIL 4: partner cannot edit a shared scrapbook'; end if;
  -- 5. Nudge: partner nudges the owner.
  perform public.nudge_partner_about_memory(sb);
  reset role;
  if not exists(select 1 from public.space_notifications where recipient_id=owner_id and kind='message' and object_id=sb) then
    raise exception 'FAIL 5: nudge notification missing'; end if;
  -- 6. Outsider cannot nudge or edit.
  perform set_config('request.jwt.claims',json_build_object('sub',c,'role','authenticated')::text,true);
  set local role authenticated;
  failed:=false;
  begin perform public.nudge_partner_about_memory(sb); exception when others then failed:=true; end;
  if not failed then raise exception 'FAIL 6: outsider nudged'; end if;
  reset role;
  raise notice 'ALL 0314 CHECKS PASSED';
end $t$;
