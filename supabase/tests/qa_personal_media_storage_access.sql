-- QA regression: personal Activity photos / voice and personal Memory photos
-- are readable only by their owner, can't be planted by others, can't go to a
-- shared bucket, and stop being readable once the photo is removed.
-- Run inside BEGIN ... ROLLBACK only. A, B: couple db24ba25-…; C: outsider.
do $t$
declare
  a uuid:='db1ac811-6fb0-4f31-8e6c-4e37b5d3a70d';
  b uuid:='77b679f8-1a70-4347-a95e-9a39d3ea6977';
  c uuid:='937e362d-6457-4fe2-b8cd-abad7157a015';
  act uuid; mem uuid; photo uuid;
  img text; voice text; mphoto text; n int; failed boolean;
begin
  perform set_config('request.jwt.claims',json_build_object('sub',a,'role','authenticated')::text,true);
  set local role authenticated;
  insert into public.activities(private_space_id,created_by,visibility,title)
   values(a,a,'private','Personal media') returning id into act;
  img:=act||'/'||a||'/'||gen_random_uuid()||'.jpg';
  voice:=act||'/'||a||'/'||gen_random_uuid()||'.m4a';
  -- 1. Owner uploads a personal Activity photo and voice note and attaches them.
  insert into storage.objects(bucket_id,name,owner_id) values('onespace-private-activity-media',img,a::text);
  insert into storage.objects(bucket_id,name,owner_id) values('onespace-private-activity-voice',voice,a::text);
  insert into public.activity_components(activity_id,created_by,kind,label,payload)
   values(act,a,'image','Photo',jsonb_build_object('object_path',img,
     'bucket_id','onespace-private-activity-media','mime','image/jpeg','note',''));
  insert into public.activity_comments(activity_id,author_id,body,voice_path,voice_bucket_id,voice_seconds)
   values(act,a,'Voice',voice,'onespace-private-activity-voice',3);
  select count(*) into n from storage.objects where name in (img,voice);
  if n<>2 then raise exception 'FAIL 1: owner cannot read own personal Activity media (%)',n; end if;
  -- 2. A personal Activity photo may not point at the shared bucket.
  failed:=false;
  begin insert into public.activity_components(activity_id,created_by,kind,label,payload)
    values(act,a,'image','Photo',jsonb_build_object('object_path',act||'/'||a||'/'||gen_random_uuid()||'.jpg',
      'bucket_id','onespace-activity-media','mime','image/jpeg','note',''));
  exception when others then failed:=true; end;
  if not failed then raise exception 'FAIL 2: personal Activity photo accepted in shared bucket'; end if;

  -- Personal Memory photo.
  insert into public.memories(private_space_id,created_by,visibility,title,body,memory_date)
   values(a,a,'private','Personal memory','',current_date) returning id into mem;
  mphoto:=mem||'/'||a||'/'||gen_random_uuid()||'.jpg';
  insert into storage.objects(bucket_id,name,owner_id) values('onespace-private-memory-photos',mphoto,a::text);
  insert into public.memory_photos(memory_id,created_by,mime_type,byte_size,object_path,storage_bucket_id)
   values(mem,a,'image/jpeg',10,mphoto,'onespace-private-memory-photos') returning id into photo;
  select count(*) into n from storage.objects where name=mphoto;
  if n<>1 then raise exception 'FAIL 3: owner cannot read own personal Memory photo'; end if;
  -- 4. Bytes of a personal Memory may not be uploaded to the shared bucket.
  failed:=false;
  begin insert into storage.objects(bucket_id,name,owner_id)
    values('onespace-memory-photos',mem||'/'||a||'/'||gen_random_uuid()||'.jpg',a::text);
  exception when others then failed:=true; end;
  if not failed then raise exception 'FAIL 4: personal Memory bytes accepted in shared bucket'; end if;
  reset role;

  -- Partner B and outsider C: no reads, no planting.
  for i in 1..2 loop
    perform set_config('request.jwt.claims',json_build_object('sub',case when i=1 then b else c end,
      'role','authenticated')::text,true);
    set local role authenticated;
    select count(*) into n from storage.objects where name in (img,voice,mphoto);
    if n<>0 then raise exception 'FAIL 5.%: another account reads personal media bytes',i; end if;
    failed:=false;
    begin insert into storage.objects(bucket_id,name,owner_id)
      values('onespace-private-activity-media',
        act||'/'||(case when i=1 then b else c end)||'/'||gen_random_uuid()||'.jpg',
        (case when i=1 then b else c end)::text);
    exception when others then failed:=true; end;
    if not failed then raise exception 'FAIL 6.%: another account uploaded into personal Activity',i; end if;
    failed:=false;
    begin insert into storage.objects(bucket_id,name,owner_id)
      values('onespace-private-memory-photos',
        mem||'/'||(case when i=1 then b else c end)||'/'||gen_random_uuid()||'.jpg',
        (case when i=1 then b else c end)::text);
    exception when others then failed:=true; end;
    if not failed then raise exception 'FAIL 7.%: another account uploaded into personal Memory',i; end if;
    reset role;
  end loop;

  -- 8. Revocation: once the owner removes the photo, its bytes stop being readable.
  perform set_config('request.jwt.claims',json_build_object('sub',a,'role','authenticated')::text,true);
  set local role authenticated;
  update public.memory_photos set archived_at=now() where id=photo;
  select count(*) into n from storage.objects where name=mphoto;
  if n<>0 then raise exception 'FAIL 8: removed personal Memory photo still readable'; end if;
  reset role;
  raise notice 'PASS: personal media Storage access checks';
end $t$;
