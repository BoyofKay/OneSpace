-- QA-only 0169: deterministic, scoped private-trip structured package PREVIEW.
-- This is NOT a portable encrypted archive, not an authorized restore, and
-- MUST NEVER be accepted as proof for leave/remove/delete lifecycle gating.
create or replace function private.qa_private_trip_structured_package(p_trip_id uuid)
returns jsonb
language plpgsql stable security definer
set search_path='' as $fn$
declare
  caller uuid := auth.uid();
  trip_record public.shared_trips%rowtype;
  source_table text;
  item_count integer;
  invalid_count integer;
  total_children integer := 0;
  payload jsonb;
  children jsonb := '{}'::jsonb;
  child_rows jsonb;
  fingerprint text;
begin
  if caller is null then raise exception 'Sign in required'; end if;
  if p_trip_id is null then raise exception 'Private trip not found'; end if;

  -- No caller-provided owner or space ID is ever trusted. A former partner
  -- and any unrelated account receive the same not-found error.
  select t.* into trip_record
  from public.shared_trips t
  join public.space_members sm on sm.space_id=t.space_id and sm.user_id=caller
  where t.id=p_trip_id and t.created_by=caller and t.visibility='private';
  if not found then raise exception 'Private trip not found'; end if;
  if (select count(*) from public.space_members sm where sm.user_id=caller)<>1 then
    raise exception 'Private trip not found';
  end if;

  if (select count(*) from private.qa_archive_table_policy p
      where p.source_table in ('shared_trips','trip_flight_options',
                               'trip_items','trip_messages')
        and p.approved and p.disposition='private_shared')<>4 then
    raise exception 'Private trip package scope has not been approved';
  end if;

  if not exists (
      select 1 from public.personal_vault_records v
       where v.owner_id=caller and v.source_table='shared_trips'
         and v.source_id=trip_record.id
         and v.source_space_id=trip_record.space_id
         and v.current_visibility='private' and v.restorable
         and v.snapshot=private.qa_structured_value(to_jsonb(trip_record))
    ) then
    raise exception 'Private trip vault is not synchronized';
  end if;

  foreach source_table in array array[
    'trip_flight_options','trip_items','trip_messages'
  ] loop
    -- Require exactly one valid owner/space/sanitized vault mirror per child.
    -- Never infer that a partner-authored child belongs to this owner.
    execute format(
      'select count(*),count(*) filter(
         where c.created_by is distinct from $2
            or v.source_id is null)
       from public.%I c
       left join public.personal_vault_dependents v
         on v.source_table=%L and v.source_id=c.id and v.owner_id=$2
        and v.parent_table=''shared_trips'' and v.parent_id=$1
        and v.source_space_id=$3 and v.restorable
        and v.snapshot=private.qa_structured_value(to_jsonb(c))
       where c.trip_id=$1',source_table,source_table
    ) into item_count,invalid_count
      using trip_record.id,caller,trip_record.space_id;
    if invalid_count>0 then
      raise exception 'Private trip child ownership or snapshot mismatch';
    end if;
    total_children:=total_children+item_count;
    if total_children>500 then
      raise exception 'Private trip package exceeds per-request record limit';
    end if;
    execute format(
      'select coalesce(jsonb_agg(
         jsonb_build_object(''source_id'',c.id,
          ''structured'',private.qa_structured_value(to_jsonb(c)))
         order by c.id::text),''[]''::jsonb)
       from public.%I c where c.trip_id=$1 and c.created_by=$2',source_table
    ) into child_rows using trip_record.id,caller;
    children:=children||jsonb_build_object(source_table,child_rows);
  end loop;

  -- Hash the stable structured payload only (no transient timestamps).
  -- SHA-256 detects corruption; it is NOT encryption or authenticity.
  payload:=jsonb_build_object(
    'schema','onespace.private-trip-structured-preview.v1',
    'source_space_id',trip_record.space_id,
    'owner_id',caller,
    'root',jsonb_build_object('table','shared_trips',
      'source_id',trip_record.id,
      'structured',private.qa_structured_value(to_jsonb(trip_record))),
    'children',children,
    'child_record_count',total_children);
  if octet_length(convert_to(payload::text,'UTF8'))>2097152 then
    raise exception 'Private trip package exceeds 2 MiB preview limit';
  end if;
  fingerprint:=encode(extensions.digest(
      convert_to(payload::text,'UTF8'),'sha256'),'hex');

  return jsonb_build_object(
    'created_at',now(),
    'payload',payload,
    'payload_sha256',fingerprint,
    'media_included',false,
    'documents_included',false,
    'encrypted',false,
    'is_verified_archive',false,
    'can_restore',false,
    'safe_to_separate',false,
    'warning','Private trip structured preview only. No encrypted/downloadable archive or restore is available.');
end $fn$;
revoke all on function private.qa_private_trip_structured_package(uuid)
  from public,anon,authenticated;
grant execute on function private.qa_private_trip_structured_package(uuid)
  to authenticated;
