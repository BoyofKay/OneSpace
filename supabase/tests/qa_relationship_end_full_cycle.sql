-- QA full separation cycle, rollback-only. Opens the relationship gate INSIDE
-- this transaction only. Uses the QA couple db24ba25-… (A and B) and outsider C.
-- Checks: wrong actor/action/phrase refused; remove partner erases ALL shared
-- rows and queues shared files; both keep every private row; both unpaired;
-- re-pairing starts with an empty shared space; leave and delete also work.
do $t$
declare
  a uuid:='db1ac811-6fb0-4f31-8e6c-4e37b5d3a70d';
  b uuid:='77b679f8-1a70-4347-a95e-9a39d3ea6977';
  c uuid:='937e362d-6457-4fe2-b8cd-abad7157a015';
  couple uuid:='db24ba25-8f22-4565-85df-b1e9edab8e00';
  owner_id uuid; guest uuid; guest_email text;
  shared_act uuid; shared_mem uuid; mine_act uuid; theirs_note uuid;
  p_before bigint; p_after bigint; n bigint; failed boolean; res jsonb;
  space2 uuid; token text;
begin
  update private.qa_relationship_v2_gate set enabled=true where id=1;
  select created_by into owner_id from public.spaces where id=couple;
  guest:=case when owner_id=a then b else a end;
  select lower(email) into guest_email from auth.users where id=guest;

  -- Content: shared Activity + shared Memory with a photo, private items.
  perform set_config('request.jwt.claims',json_build_object('sub',owner_id,'role','authenticated')::text,true);
  set local role authenticated;
  insert into public.activities(space_id,created_by,visibility,title)
   values(couple,owner_id,'shared','Our plan') returning id into shared_act;
  insert into public.activity_comments(activity_id,author_id,body) values(shared_act,owner_id,'Shared chat');
  insert into public.memories(space_id,created_by,visibility,title,body,memory_date)
   values(couple,owner_id,'shared','Our day','',current_date) returning id into shared_mem;
  insert into public.memory_photos(memory_id,created_by,mime_type,byte_size,object_path)
   values(shared_mem,owner_id,'image/jpeg',10,shared_mem||'/'||owner_id||'/'||gen_random_uuid()||'.jpg');
  insert into public.activities(private_space_id,created_by,visibility,title)
   values(owner_id,owner_id,'private','Owner private') returning id into mine_act;
  reset role;
  perform set_config('request.jwt.claims',json_build_object('sub',guest,'role','authenticated')::text,true);
  set local role authenticated;
  insert into public.notes(private_space_id,created_by,visibility,title,body)
   values(guest,guest,'private','Guest private','') returning id into theirs_note;
  insert into public.notes(space_id,created_by,visibility,title,body)
   values(couple,guest,'shared','Guest shared note','');
  -- 1. The guest may not remove the owner, and the phrase must be exact.
  failed:=false;
  begin perform public.qa_end_current_relationship(couple,'remove_partner','DELETE SHARED CONTENT');
  exception when others then failed:=true; end;
  if not failed then raise exception 'FAIL 1: guest removed the owner'; end if;
  failed:=false;
  begin perform public.qa_end_current_relationship(couple,'leave_space','delete shared content');
  exception when others then failed:=true; end;
  if not failed then raise exception 'FAIL 2: wrong confirmation phrase accepted'; end if;
  reset role;
  -- 3. An outsider can't end someone else's relationship.
  perform set_config('request.jwt.claims',json_build_object('sub',c,'role','authenticated')::text,true);
  set local role authenticated;
  failed:=false;
  begin perform public.qa_end_current_relationship(couple,'delete_space','DELETE SHARED CONTENT');
  exception when others then failed:=true; end;
  if not failed then raise exception 'FAIL 3: outsider ended another couple'; end if;
  reset role;

  -- Count every private row of both people before.
  select sum(cnt) into p_before from (
    select (xpath('/row/c/text()',query_to_xml(format(
      'select count(*) c from public.%I where private_space_id in (%L,%L)',
      table_name,owner_id,guest),false,true,'')))[1]::text::bigint cnt
    from information_schema.columns where table_schema='public'
     and column_name='private_space_id') x;

  -- 4. The owner removes the partner.
  perform set_config('request.jwt.claims',json_build_object('sub',owner_id,'role','authenticated')::text,true);
  set local role authenticated;
  res:=public.qa_end_current_relationship(couple,'remove_partner','DELETE SHARED CONTENT');
  reset role;
  if res->>'status' is null then raise exception 'FAIL 4: remove partner returned nothing'; end if;
  if exists(select 1 from public.spaces where id=couple) then raise exception 'FAIL 5: shared space still exists'; end if;
  if exists(select 1 from public.space_members where space_id=couple) then raise exception 'FAIL 6: membership remains'; end if;
  if exists(select 1 from public.activities where id=shared_act)
     or exists(select 1 from public.activity_comments where activity_id=shared_act)
     or exists(select 1 from public.memories where id=shared_mem)
     or exists(select 1 from public.memory_photos where memory_id=shared_mem)
     or exists(select 1 from public.notes where space_id=couple) then
    raise exception 'FAIL 7: shared content survived'; end if;
  select count(*) into n from public.qa_shared_media_purge_queue where space_id=couple and deleted_at is null;
  if n<1 then raise exception 'FAIL 8: shared photo not queued for file deletion'; end if;
  select sum(cnt) into p_after from (
    select (xpath('/row/c/text()',query_to_xml(format(
      'select count(*) c from public.%I where private_space_id in (%L,%L)',
      table_name,owner_id,guest),false,true,'')))[1]::text::bigint cnt
    from information_schema.columns where table_schema='public'
     and column_name='private_space_id') x;
  if p_after<>p_before then raise exception 'FAIL 9: private rows changed % -> %',p_before,p_after; end if;
  if not exists(select 1 from public.activities where id=mine_act)
     or not exists(select 1 from public.notes where id=theirs_note) then
    raise exception 'FAIL 10: a private item was lost'; end if;

  -- 11. Both are unpaired and still see their own private items.
  perform set_config('request.jwt.claims',json_build_object('sub',guest,'role','authenticated')::text,true);
  set local role authenticated;
  if (public.my_storage_scopes()->>'shared_space_id') is not null then raise exception 'FAIL 11: guest still paired'; end if;
  if not exists(select 1 from public.notes where id=theirs_note) then raise exception 'FAIL 12: guest lost own note'; end if;
  reset role;

  -- 13. Re-pairing starts clean: owner makes a new space and invites the guest.
  perform set_config('request.jwt.claims',json_build_object('sub',owner_id,'role','authenticated')::text,true);
  set local role authenticated;
  space2:=public.create_space();
  token:=public.create_addressed_invitation(space2,guest_email,false);
  reset role;
  perform set_config('request.jwt.claims',json_build_object('sub',guest,'role','authenticated')::text,true);
  set local role authenticated;
  perform public.accept_invitation(token);
  select count(*) into n from public.activities where space_id=space2;
  if n<>0 then raise exception 'FAIL 13: new space inherited shared content'; end if;
  if exists(select 1 from public.notes where space_id=couple) then raise exception 'FAIL 14: old shared notes visible'; end if;
  reset role;
  -- 14b. The owner is told the partner joined (0309).
  if not exists(select 1 from public.space_notifications
     where recipient_id=owner_id and kind='joined' and object_id=space2) then
    raise exception 'FAIL 14b: no partner-joined notification'; end if;
  perform set_config('request.jwt.claims',json_build_object('sub',guest,'role','authenticated')::text,true);
  set local role authenticated;
  -- 15. The invited partner can leave the new space.
  res:=public.qa_end_current_relationship(space2,'leave_space','DELETE SHARED CONTENT');
  reset role;
  if exists(select 1 from public.space_members where space_id=space2) then raise exception 'FAIL 15: leave did not unpair'; end if;

  -- 16. Amr's case: a person alone in a space deletes it, then can join elsewhere.
  perform set_config('request.jwt.claims',json_build_object('sub',guest,'role','authenticated')::text,true);
  set local role authenticated;
  space2:=public.create_space();
  res:=public.qa_end_current_relationship(space2,'delete_space','DELETE SHARED CONTENT');
  if exists(select 1 from public.space_members where user_id=guest) then raise exception 'FAIL 16: solo delete left a membership'; end if;
  if not exists(select 1 from public.notes where id=theirs_note) then raise exception 'FAIL 17: solo delete lost private note'; end if;
  reset role;
  raise notice 'PASS: full relationship-end cycle';
end $t$;
