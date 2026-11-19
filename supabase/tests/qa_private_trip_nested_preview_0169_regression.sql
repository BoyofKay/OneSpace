-- QA-only rollback regression. Existing QA users are a fixture; created
-- trip/child records are synthetic and never committed.
begin;
do $qa$
declare
  sid uuid;
  owner_user uuid;
  partner_user uuid;
  trip_id uuid;
  one uuid;
  pack jsonb;
  pack2 jsonb;
  err text;
  payload jsonb;
  fingerprint text;
begin
  select s.id,s.created_by,m.user_id into sid,owner_user,partner_user
    from public.spaces s join public.space_members m
      on m.space_id=s.id and m.user_id<>s.created_by
   where (select count(*) from public.space_members sm where sm.space_id=s.id)=2
   limit 1;
  if sid is null then raise exception 'A paired QA fixture is required';end if;
  if has_function_privilege('anon',
     'private.qa_private_trip_structured_package(uuid)','execute') then
    raise exception 'Anonymous access to nested preview is forbidden';
  end if;
  insert into public.shared_trips(space_id,created_by,title,visibility,notes)
    values(sid,owner_user,'QA NESTED PRIVATE TRIP','private','Owner-only trip notes')
    returning id into trip_id;
  insert into public.trip_flight_options(trip_id,created_by,title,notes)
    values(trip_id,owner_user,'Owner private flight','Flight notes');
  insert into public.trip_items(trip_id,created_by,kind,title,details)
    values(trip_id,owner_user,'note','Owner private itinerary','Only the owner sees this');
  insert into public.trip_messages(trip_id,created_by,body)
    values(trip_id,owner_user,
     'Keep written text, not https://foo.example/storage/v1/object/private/private-image.jpg')
    returning id into one;

  perform set_config('role','authenticated',true);
  perform set_config('request.jwt.claim.sub',owner_user::text,true);
  pack:=private.qa_private_trip_structured_package(trip_id);
  payload:=pack->'payload';
  if payload->>'owner_id'<>owner_user::text
    or payload->>'source_space_id'<>sid::text
    or payload->>'schema'<>'onespace.private-trip-structured-preview.v1'
    or (payload->>'child_record_count')::int<>3
    or jsonb_array_length(payload#>'{children,trip_flight_options}')<>1
    or jsonb_array_length(payload#>'{children,trip_items}')<>1
    or jsonb_array_length(payload#>'{children,trip_messages}')<>1
    or pack->>'encrypted'<>'false'
    or pack->>'is_verified_archive'<>'false'
    or pack->>'can_restore'<>'false'
    or pack->>'safe_to_separate'<>'false'
  then raise exception 'Incorrect nested scope or safety flags';end if;
  if pack::text like '%storage/v1/object%'
     or pack::text not like '%Keep written text%'
     or pack::text not like '%Owner private itinerary%' then
    raise exception 'Nested preview failed media sanitation or retained no text';end if;

  fingerprint:=encode(extensions.digest(convert_to(payload::text,'UTF8'),'sha256'),'hex');
  if pack->>'payload_sha256'<>fingerprint then
    raise exception 'Nested payload SHA-256 does not match';end if;
  pack2:=private.qa_private_trip_structured_package(trip_id);
  if pack2->>'payload_sha256'<>pack->>'payload_sha256' then
    raise exception 'Unchanged structured preview has unstable hash';end if;

  perform set_config('request.jwt.claim.sub',partner_user::text,true);
  begin
    perform private.qa_private_trip_structured_package(trip_id);
    raise exception 'Partner accessed owner-only trip preview';
  exception when others then
    get stacked diagnostics err=message_text;
    if err<>'Private trip not found' then
      raise exception 'Wrong private access behavior: %',err;
    end if;
  end;

  perform set_config('request.jwt.claim.sub',owner_user::text,true);
  update public.shared_trips set visibility='shared' where id=trip_id;
  begin
    perform private.qa_private_trip_structured_package(trip_id);
    raise exception 'Shared trip passed as owner-private';
  exception when others then
    get stacked diagnostics err=message_text;
    if err<>'Private trip not found' then
      raise exception 'Wrong shared transition behavior: %',err;
    end if;
  end;
  update public.shared_trips set visibility='private' where id=trip_id;
  pack2:=private.qa_private_trip_structured_package(trip_id);
  if pack2->>'payload_sha256'=pack->>'payload_sha256' then
    -- Visibility transition updates updated_at, so the payload hash may differ;
    -- the important check is that the resynchronized preview exists.
    null;
  end if;
  if (pack2->'payload'->>'child_record_count')::int<>3 then
    raise exception 'Re-private snapshots were not resynchronized';end if;

  perform set_config('role','postgres',true);
  update public.personal_vault_dependents
    set snapshot='{}'::jsonb
  where owner_id=owner_user and source_table='trip_messages'
    and source_id=one and restorable;
  perform set_config('role','authenticated',true);
  begin
    perform private.qa_private_trip_structured_package(trip_id);
    raise exception 'Corrupted private vault did not fail closed';
  exception when others then
    get stacked diagnostics err=message_text;
    if err<>'Private trip child ownership or snapshot mismatch' then
      raise exception 'Wrong corrupt-vault behavior: %',err;
    end if;
  end;
end $qa$;
rollback;
select 'PASS: nested private-trip payload, hash, no media, owner-only access, visibility transitions, corrupt-vault fail-closed; all synthetic fixtures rolled back' result;
