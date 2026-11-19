-- QA-only: preserve private trip child records across clean-space transitions.
-- No media files or blobs, no deletion/restore enablement, no Production changes.
create or replace function private.qa_mirror_trip_child()
returns trigger language plpgsql security definer set search_path='' as $fn$
declare
  v_owner uuid;
  v_visibility text;
  v_space uuid;
begin
  if tg_table_schema<>'public' or tg_table_name not in
    ('trip_flight_options','trip_items','trip_messages') then
    raise exception 'Unexpected private trip child source';
  end if;
  if tg_op='DELETE' then
    if current_setting('onespace.retiring_space',true)<>'on' then
      update public.personal_vault_dependents
        set restorable=false,snapshot='{}'::jsonb,last_mirrored_at=now()
       where owner_id=old.created_by and source_table=tg_table_name
         and source_id=old.id;
    end if;
    return old;
  end if;
  if tg_op='UPDATE' and
     (new.created_by is distinct from old.created_by
      or new.trip_id is distinct from old.trip_id) then
    update public.personal_vault_dependents
      set restorable=false,snapshot='{}'::jsonb,last_mirrored_at=now()
    where owner_id=old.created_by and source_table=tg_table_name
      and source_id=old.id;
  end if;
  select p.created_by,p.visibility,p.space_id into v_owner,v_visibility,v_space
  from public.shared_trips p where p.id=new.trip_id;
  if v_visibility='private' then
    if new.created_by is distinct from v_owner then
      raise exception 'Private trip child must belong to trip owner';
    end if;
    if not exists(select 1 from public.personal_vault_records v
       where v.owner_id=v_owner and v.source_table='shared_trips'
       and v.source_id=new.trip_id and v.source_space_id=v_space
       and v.current_visibility='private' and v.restorable) then
      raise exception 'Private trip root snapshot missing';
    end if;
    insert into public.personal_vault_dependents
      (owner_id,parent_table,parent_id,source_table,source_id,source_space_id,snapshot)
    values(new.created_by,'shared_trips',new.trip_id,tg_table_name,
           new.id,v_space,private.qa_structured_value(to_jsonb(new)))
    on conflict(owner_id,source_table,source_id) do update set
      parent_table=excluded.parent_table,parent_id=excluded.parent_id,
      source_space_id=excluded.source_space_id,snapshot=excluded.snapshot,
      restorable=true,last_mirrored_at=now();
  else
    -- Shared trip descendants must never remain marked as restorable private.
    update public.personal_vault_dependents
      set restorable=false,snapshot='{}'::jsonb,last_mirrored_at=now()
    where owner_id=new.created_by and source_table=tg_table_name
      and source_id=new.id;
  end if;
  return new;
end $fn$;
revoke all on function private.qa_mirror_trip_child() from public,anon,authenticated;

-- Called after the existing root-vault trigger whenever the trip's
-- visibility, account owner or space changes.
create or replace function private.qa_sync_private_trip_children(p_trip_id uuid)
returns void language plpgsql security definer set search_path='' as $fn$
declare
  v_trip public.shared_trips%rowtype;
  source_table text;
  mismatch_count bigint;
begin
  select * into v_trip from public.shared_trips where id=p_trip_id;
  if not found then return; end if;
  if v_trip.visibility<>'private' then
    update public.personal_vault_dependents
      set restorable=false,snapshot='{}'::jsonb,last_mirrored_at=now()
    where parent_table='shared_trips' and parent_id=p_trip_id;
    return;
  end if;
  if not exists(select 1 from public.personal_vault_records v
    where v.owner_id=v_trip.created_by and v.source_table='shared_trips'
    and v.source_id=v_trip.id and v.source_space_id=v_trip.space_id
    and v.restorable and v.current_visibility='private') then
    raise exception 'Private trip root vault must exist before child sync';
  end if;
  foreach source_table in array array[
    'trip_flight_options','trip_items','trip_messages'
  ] loop
    execute format('select count(*) from public.%I c
      where c.trip_id=$1 and c.created_by is distinct from $2',source_table)
    into mismatch_count using p_trip_id,v_trip.created_by;
    if mismatch_count>0 then
      raise exception 'Private trip contains child owned by another account';
    end if;
    execute format(
      'insert into public.personal_vault_dependents
        (owner_id,parent_table,parent_id,source_table,source_id,source_space_id,snapshot)
       select $1,''shared_trips'',$2,%L,c.id,$3,
         private.qa_structured_value(to_jsonb(c))
       from public.%I c where c.trip_id=$2 and c.created_by=$1
       on conflict(owner_id,source_table,source_id) do update set
         parent_table=excluded.parent_table,parent_id=excluded.parent_id,
         source_space_id=excluded.source_space_id,snapshot=excluded.snapshot,
         restorable=true,last_mirrored_at=now()',source_table,source_table)
    using v_trip.created_by,v_trip.id,v_trip.space_id;
  end loop;
end $fn$;
revoke all on function private.qa_sync_private_trip_children(uuid)
from public,anon,authenticated;

create or replace function private.qa_trip_children_on_parent_change()
returns trigger language plpgsql security definer set search_path='' as $fn$
begin
  if tg_op='UPDATE' and old.created_by is distinct from new.created_by then
    update public.personal_vault_dependents
      set restorable=false,snapshot='{}'::jsonb,last_mirrored_at=now()
    where owner_id=old.created_by and parent_table='shared_trips'
      and parent_id=old.id;
  end if;
  perform private.qa_sync_private_trip_children(new.id);
  return new;
end $fn$;
revoke all on function private.qa_trip_children_on_parent_change()
from public,anon,authenticated;

create trigger qa_trip_children_on_parent_change
after update of visibility,created_by,space_id on public.shared_trips
for each row execute function private.qa_trip_children_on_parent_change();

create trigger qa_trip_vault_mirror after insert or update or delete
on public.trip_flight_options for each row
execute function private.qa_mirror_trip_child();
create trigger qa_trip_vault_mirror after insert or update or delete
on public.trip_items for each row
execute function private.qa_mirror_trip_child();
create trigger qa_trip_vault_mirror after insert or update or delete
on public.trip_messages for each row
execute function private.qa_mirror_trip_child();

-- Backfill existing private QA trip descendants without touching user content.
do $backfill$
declare trip_record record;
begin
  for trip_record in select id from public.shared_trips where visibility='private' loop
    perform private.qa_sync_private_trip_children(trip_record.id);
  end loop;
end $backfill$;
