-- QA regression for 0305 (personal scrapbooks + Memory photo bucket scope).
-- Run inside BEGIN ... ROLLBACK only. Uses existing QA accounts:
--   A, B: the current couple db24ba25-…; C: an account outside that couple.
-- Each step raises on failure, so a clean run means every check passed.
do $t$
declare
  a uuid:='db1ac811-6fb0-4f31-8e6c-4e37b5d3a70d';
  b uuid:='77b679f8-1a70-4347-a95e-9a39d3ea6977';
  c uuid:='937e362d-6457-4fe2-b8cd-abad7157a015';
  couple uuid:='db24ba25-8f22-4565-85df-b1e9edab8e00';
  personal uuid; shared uuid; page uuid; n int; failed boolean;
begin
  -- A creates a private scrapbook without naming any couple.
  perform set_config('request.jwt.claims',json_build_object('sub',a,'role','authenticated')::text,true);
  set local role authenticated;
  personal:=public.create_scrapbook(null,'Mine','polaroid_letters','private',current_date);
  select count(*) into n from public.memories
   where id=personal and private_space_id=a and space_id is null and visibility='private';
  if n<>1 then raise exception 'FAIL 1: private scrapbook not account-owned'; end if;
  select count(*) into n from public.scrapbook_pages where memory_id=personal;
  if n<>1 then raise exception 'FAIL 2: owner cannot see first page'; end if;
  insert into public.scrapbook_pages(memory_id,page_order,template_key)
   values(personal,1,'polaroid_letters') returning id into page;
  update public.scrapbook_pages set title='Edited' where id=page;
  -- A personal photo row may not point at the shared bucket.
  failed:=false;
  begin
    insert into public.memory_photos(memory_id,created_by,mime_type,byte_size,object_path)
     values(personal,a,'image/jpeg',10,personal||'/'||a||'/'||gen_random_uuid()||'.jpg');
  exception when others then failed:=true; end;
  if not failed then raise exception 'FAIL 3: personal photo accepted in shared bucket'; end if;
  insert into public.memory_photos(memory_id,created_by,mime_type,byte_size,object_path,storage_bucket_id)
   values(personal,a,'image/jpeg',10,personal||'/'||a||'/'||gen_random_uuid()||'.jpg','onespace-private-memory-photos');
  -- A shared scrapbook needs the current couple.
  shared:=public.create_scrapbook(couple,'Ours','polaroid_letters','shared',current_date);
  failed:=false;
  begin perform public.create_scrapbook(null,'X','polaroid_letters','shared',current_date);
  exception when others then failed:=true; end;
  if not failed then raise exception 'FAIL 4: shared scrapbook without a couple'; end if;
  reset role;

  -- Partner B never sees or edits A's personal scrapbook, but sees the shared one.
  perform set_config('request.jwt.claims',json_build_object('sub',b,'role','authenticated')::text,true);
  set local role authenticated;
  select count(*) into n from public.memories where id=personal;
  if n<>0 then raise exception 'FAIL 5: partner sees personal scrapbook'; end if;
  select count(*) into n from public.scrapbook_pages where memory_id=personal;
  if n<>0 then raise exception 'FAIL 6: partner sees personal pages'; end if;
  select count(*) into n from public.memory_photos where memory_id=personal;
  if n<>0 then raise exception 'FAIL 7: partner sees personal photo rows'; end if;
  failed:=false;
  begin insert into public.scrapbook_pages(memory_id,page_order,template_key)
    values(personal,5,'polaroid_letters');
  exception when others then failed:=true; end;
  if not failed then raise exception 'FAIL 8: partner added a page to personal scrapbook'; end if;
  update public.scrapbook_pages set title='Hijack' where memory_id=personal;
  get diagnostics n=row_count;
  if n<>0 then raise exception 'FAIL 9: partner edited personal pages'; end if;
  select count(*) into n from public.memories where id=shared;
  if n<>1 then raise exception 'FAIL 10: partner cannot see shared scrapbook'; end if;
  reset role;

  -- An outsider sees neither.
  perform set_config('request.jwt.claims',json_build_object('sub',c,'role','authenticated')::text,true);
  set local role authenticated;
  select count(*) into n from public.memories where id in (personal,shared);
  if n<>0 then raise exception 'FAIL 11: outsider sees scrapbooks'; end if;
  failed:=false;
  begin perform public.create_scrapbook(couple,'Intrude','polaroid_letters','shared',current_date);
  exception when others then failed:=true; end;
  if not failed then raise exception 'FAIL 12: outsider created in another couple'; end if;
  reset role;
  raise notice 'PASS: 12 personal scrapbook and photo-scope checks';
end $t$;
