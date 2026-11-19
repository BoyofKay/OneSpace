-- QA rollback-only regression: private trip child archives survive visibility
-- changes and exclude file data; unauthorized child authors are rejected.
begin;
do $test$
declare
  sid uuid; v_owner_id uuid; partner_id uuid; trip_id uuid;
  flight_id uuid; item_id uuid; message_id uuid;
  n int; err text; msg jsonb;
begin
  select sp.id,sp.created_by,sm.user_id into sid,v_owner_id,partner_id
  from public.spaces sp join public.space_members sm
    on sm.space_id=sp.id and sm.user_id<>sp.created_by
  where (select count(*) from public.space_members m where m.space_id=sp.id)=2
  limit 1;
  if sid is null then raise exception 'Paired QA fixture missing'; end if;
  insert into public.shared_trips(space_id,created_by,title,visibility)
    values(sid,v_owner_id,'QA PRIVATE VAULT TRIP', 'private') returning id into trip_id;
  insert into public.trip_flight_options(trip_id,created_by,title)
    values(trip_id,v_owner_id,'Private flight') returning id into flight_id;
  insert into public.trip_items(trip_id,created_by,kind,title,details)
    values(trip_id,v_owner_id,'note','Private itinerary','Private preparation note')
    returning id into item_id;
  insert into public.trip_messages(trip_id,created_by,body)
    values(trip_id,v_owner_id,'A memory and https://example.com/storage/v1/object/private/a.jpg')
    returning id into message_id;

  select count(*) into n from public.personal_vault_dependents d
   where d.owner_id=v_owner_id and d.parent_table='shared_trips'
     and d.parent_id=trip_id and d.restorable;
  if n<>3 then raise exception 'Expected 3 private trip snapshots, found %',n; end if;
  select snapshot into msg from public.personal_vault_dependents
   where v_owner_id=v_owner_id and source_table='trip_messages' and source_id=message_id;
  if msg::text like '%storage/v1/object%'
     or msg::text not like '%A memory%' then
    raise exception 'Media stripping erased text or retained Storage URL'; end if;

  update public.shared_trips set visibility='shared' where id=trip_id;
  select count(*) into n from public.personal_vault_dependents
   where parent_id=trip_id and restorable;
  if n<>0 then raise exception 'Shared trip retained private child snapshots';end if;
  update public.shared_trips set visibility='private' where id=trip_id;
  select count(*) into n from public.personal_vault_dependents
   where parent_id=trip_id and v_owner_id=v_owner_id and restorable;
  if n<>3 then raise exception 'Restored privacy did not backfill 3 children: %',n;end if;

  begin
    insert into public.trip_messages(trip_id,created_by,body)
    values(trip_id,partner_id,'Must not enter owner private trip');
    raise exception 'Mismatched author was accepted';
  exception when others then
    get stacked diagnostics err=message_text;
    if err not like 'Private trip child must belong to trip owner%' then
      raise exception 'Wrong rejection for privacy violation: %',err;
    end if;
  end;
  delete from public.trip_messages where id=message_id;
  if exists(select 1 from public.personal_vault_dependents
      where source_table='trip_messages' and source_id=message_id and restorable)
  then raise exception 'Deleted private trip message remains restorable';end if;
  if has_function_privilege('anon','private.qa_sync_private_trip_children(uuid)','execute')
     or has_function_privilege('authenticated','private.qa_sync_private_trip_children(uuid)','execute')
     or has_function_privilege('anon','private.qa_mirror_trip_child()','execute')
  then raise exception 'Internal vault helper has public execution';end if;
end $test$;
rollback;
select 'PASS: private trip children mirrored, sanitized, invalidated, reinstated, author checked and deletion tombstoned; rolled back' result;
