-- QA regression for 0306 (personal reminder sources). BEGIN ... ROLLBACK only.
do $t$
declare
  a uuid:='db1ac811-6fb0-4f31-8e6c-4e37b5d3a70d';
  b uuid:='77b679f8-1a70-4347-a95e-9a39d3ea6977';
  couple uuid:='db24ba25-8f22-4565-85df-b1e9edab8e00';
  mine uuid; ours uuid; theirs uuid; r uuid; failed boolean;
begin
  perform set_config('request.jwt.claims',json_build_object('sub',b,'role','authenticated')::text,true);
  set local role authenticated;
  insert into public.activities(private_space_id,created_by,visibility,title)
   values(b,b,'private','B personal') returning id into theirs;
  reset role;

  perform set_config('request.jwt.claims',json_build_object('sub',a,'role','authenticated')::text,true);
  set local role authenticated;
  insert into public.activities(private_space_id,created_by,visibility,title)
   values(a,a,'private','A personal') returning id into mine;
  insert into public.activities(space_id,created_by,visibility,title)
   values(couple,a,'shared','Shared') returning id into ours;
  -- 1. Own personal Activity: allowed.
  insert into public.reminders(private_space_id,created_by,visibility,audience,title,due_at,source_kind,source_id)
   values(a,a,'private','me','Remind me',now()+interval '1 day','activity',mine) returning id into r;
  if r is null then raise exception 'FAIL 1: own personal source refused'; end if;
  -- 2. Couple Activity from a personal reminder: refused.
  failed:=false;
  begin insert into public.reminders(private_space_id,created_by,visibility,audience,title,due_at,source_kind,source_id)
    values(a,a,'private','me','x',now()+interval '1 day','activity',ours);
  exception when others then failed:=true; end;
  if not failed then raise exception 'FAIL 2: personal reminder linked to shared item'; end if;
  -- 3. Partner's personal Activity: refused.
  failed:=false;
  begin insert into public.reminders(private_space_id,created_by,visibility,audience,title,due_at,source_kind,source_id)
    values(a,a,'private','me','x',now()+interval '1 day','activity',theirs);
  exception when others then failed:=true; end;
  if not failed then raise exception 'FAIL 3: personal reminder linked to partner item'; end if;
  -- 4. Source without kind: refused by policy.
  failed:=false;
  begin insert into public.reminders(private_space_id,created_by,visibility,audience,title,due_at,source_id)
    values(a,a,'private','me','x',now()+interval '1 day',mine);
  exception when others then failed:=true; end;
  if not failed then raise exception 'FAIL 4: half-specified source accepted'; end if;
  -- 5. Source stays immutable on a personal reminder.
  failed:=false;
  begin update public.reminders set source_id=ours where id=r;
  exception when others then failed:=true; end;
  if not failed then raise exception 'FAIL 5: personal reminder source changed'; end if;
  -- 7. The owner can still edit a sourced personal reminder.
  update public.reminders set title='Edited' where id=r;
  if not exists(select 1 from public.reminders where id=r and title='Edited'
     and source_id=mine) then
    raise exception 'FAIL 7: owner cannot edit sourced personal reminder'; end if;
  reset role;

  -- 6. Partner cannot see A's personal reminder.
  perform set_config('request.jwt.claims',json_build_object('sub',b,'role','authenticated')::text,true);
  set local role authenticated;
  if exists(select 1 from public.reminders where id=r) then
    raise exception 'FAIL 6: partner sees personal reminder'; end if;
  reset role;
  raise notice 'PASS: 7 personal reminder source checks';
end $t$;
