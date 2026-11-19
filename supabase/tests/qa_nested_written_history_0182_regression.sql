-- QA 0182: rollback-only owner, shared collaborator and media exclusion.
begin;
do $qa$
declare
  sid uuid; owner_user uuid; partner_user uuid; outsider uuid;
  mid uuid; tid uuid; cid uuid;
  p jsonb; q jsonb; text_value text; msg text;
  trip_rev bigint;
  contact_rev bigint;
begin
  select s.id,s.created_by,m.user_id into sid,owner_user,partner_user
   from public.spaces s join public.space_members m
     on m.space_id=s.id and m.user_id<>s.created_by
   where (select count(*) from public.space_members k where k.space_id=s.id)=2
   limit 1;
  if sid is null then raise exception 'Paired QA fixture unavailable';end if;
  select u.id into outsider from auth.users u
    where not exists(select 1 from public.space_members x
      where x.space_id=sid and x.user_id=u.id) limit 1;

  insert into public.memories(space_id,created_by,title,memory_date,visibility,body)
   values(sid,owner_user,'QA story page',date '2026-11-20','shared','Memorable story')
   returning id into mid;
  insert into public.scrapbook_pages(memory_id,created_by,page_order,title,story_text)
   values(mid,partner_user,0,'A collaborative page',
    'A beautiful story /storage/v1/object/public/qa-secret.jpg');

  insert into public.shared_trips(space_id,created_by,title,visibility)
   values(sid,owner_user,'QA original trip','private')
   returning id into tid;
  insert into public.trip_revisions(trip_id,record_kind,record_id,changed_by,
    before_snapshot,after_snapshot)
   values(tid,'trip',tid,owner_user,
     '{"title":"Before","photo_1_id":"77777777-2222-4333-8444-555555555555"}'::jsonb,
     '{"title":"After the trip","notes":"Look at /storage/v1/object/public/secret.jpg"}'::jsonb)
   returning id into trip_rev;

  insert into public.saved_contacts(space_id,created_by,visibility,label,payload)
   values(sid,owner_user,'private','QA family member','{"phone":"123"}'::jsonb)
   returning id into cid;
  insert into public.saved_contact_revisions(contact_id,change_kind,changed_by,
    old_payload,new_payload)
   values(cid,'edited',owner_user,
     '{"note":"Old memorable line","image_2_id":"88888888-2222-4333-8444-555555555555"}'::jsonb,
     '{"note":"New family detail","photo_url":"https://example.org/storage/v1/object/x"}'::jsonb)
   returning id into contact_rev;
  if has_function_privilege('anon',
    'private.qa_nested_written_history_preview(text,uuid)','execute') then
    raise exception 'Anonymous written-history function callable';end if;

  perform set_config('role','authenticated',true);
  perform set_config('request.jwt.claim.sub',owner_user::text,true);
  p:=private.qa_nested_written_history_preview('shared_trips',tid);
  if p#>>'{payload,kind}'<>'private_owner_only'
    or p#>>'{payload,child_record_count}'<>'1'
    or p::text not like '%After the trip%'
    or p::text like '%photo_1_id%'
    or p::text like '%/storage/v1/object%'
    or p->>'can_restore'<>'false'
    or p->>'is_verified_archive'<>'false' then
    raise exception 'Private trip revision package unsafe: %',left(p::text,1300);end if;
  q:=private.qa_nested_written_history_preview('saved_contacts',cid);
  if q::text not like '%New family detail%'
    or q::text like '%image_2_id%'
    or q::text like '%storage/v1/object%'
  then raise exception 'Contact audit excluded prose or retained media';end if;
  text_value:=encode(extensions.digest(
    convert_to((p->'payload')::text,'UTF8'),'sha256'),'hex');
  if p->>'payload_sha256'<>text_value then
    raise exception 'Nested history digest mismatch';end if;

  p:=private.qa_nested_written_history_preview('memories',mid);
  if p#>>'{payload,kind}'<>'shared_reference_only'
    or p#>>'{payload,child_record_count}'<>'1'
    or p::text not like '%A collaborative page%'
    or p::text like '%/storage/v1/object%' then
    raise exception 'Shared scrapbook narrative unsafe';end if;
  perform set_config('request.jwt.claim.sub',partner_user::text,true);
  p:=private.qa_nested_written_history_preview('memories',mid);
  if p#>>'{payload,recipient_id}'<>partner_user::text
    or p::text not like '%A collaborative page%' then
    raise exception 'Partner lost shared scrapbook story';end if;
  for text_value in select unnest(array['shared_trips','saved_contacts']) loop
    begin
      perform private.qa_nested_written_history_preview(
        text_value,case when text_value='shared_trips' then tid else cid end);
      raise exception 'Partner accessed private written history';
    exception when others then
      get stacked diagnostics msg=message_text;
      if msg<>'Written-history root not found' then
        raise exception 'Wrong private-denial outcome: %',msg;end if;
    end;
  end loop;
  if outsider is not null then
    perform set_config('request.jwt.claim.sub',outsider::text,true);
    begin
      perform private.qa_nested_written_history_preview('memories',mid);
      raise exception 'Outsider accessed relationship scrapbook';
    exception when others then
      get stacked diagnostics msg=message_text;
      if msg<>'Written-history root not found' then
        raise exception 'Unexpected outsider result: %',msg;end if;
    end;
  end if;

  -- Historical partner-authored pages cannot become private owner content
  -- just because the parent visibility switched.
  perform set_config('role','postgres',true);
  update public.memories set visibility='private' where id=mid;
  perform set_config('role','authenticated',true);
  perform set_config('request.jwt.claim.sub',owner_user::text,true);
  begin
    perform private.qa_nested_written_history_preview('memories',mid);
    raise exception 'Partner-created private scrapbook was silently absorbed';
  exception when others then
    get stacked diagnostics msg=message_text;
    if msg<>'Written-history contributor lineage mismatch' then
      raise exception 'Wrong private scrapbook collision denial: %',msg;end if;
  end;
  perform set_config('role','postgres',true);
  update public.trip_revisions set changed_by=partner_user where id=trip_rev;
  perform set_config('role','authenticated',true);
  begin
    perform private.qa_nested_written_history_preview('shared_trips',tid);
    raise exception 'Other author revision accepted under private trip';
  exception when others then
    get stacked diagnostics msg=message_text;
    if msg<>'Written-history contributor lineage mismatch' then
      raise exception 'Wrong private audit collision denial: %',msg;end if;
  end;
end $qa$;
rollback;
select 'PASS: 3 nested types, shared/private scope, partner-private denial, sanitizer/prose, deterministic hash and cross-author collision rejection; rolled back' result;
