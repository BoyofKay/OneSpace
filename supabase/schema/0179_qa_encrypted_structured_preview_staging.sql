-- QA 0179: dedicated staging lane for encrypted private structured *previews*.
-- Never insert previews into space_archives; this table cannot authorize leave,
-- remove partner, delete-space, restore, or account deletion.
create or replace function public.qa_private_structured_package(
  p_source_table text,p_source_id uuid
) returns jsonb language plpgsql stable security invoker set search_path='' as $fn$
begin
  if auth.uid() is null then raise exception 'Sign in required'; end if;
  if p_source_table='shared_trips' then
    return private.qa_private_trip_structured_package(p_source_id);
  elsif p_source_table='tasks' then
    return private.qa_private_task_checklist_package(p_source_id);
  end if;
  raise exception 'Unsupported private preview source';
end $fn$;
revoke all on function public.qa_private_structured_package(text,uuid)
  from public,anon;
grant execute on function public.qa_private_structured_package(text,uuid)
  to authenticated;

create table public.qa_structured_preview_staging (
  id uuid primary key default gen_random_uuid(),
  recipient_id uuid not null references auth.users(id) on delete cascade,
  source_space_id uuid not null,
  source_table text not null check (source_table in ('shared_trips','tasks')),
  source_id uuid not null,
  status text not null default 'pending'
    check(status in ('pending','available','failed','purged')),
  object_path text not null unique,
  object_sha256 text check(object_sha256 is null or object_sha256 ~ '^[0-9a-f]{64}$'),
  byte_length integer check(byte_length is null or byte_length between 1 and 5242880),
  verified_storage_bytes boolean not null default false,
  is_verified_archive boolean not null default false
    check(is_verified_archive=false),
  can_restore boolean not null default false
    check(can_restore=false),
  safe_to_separate boolean not null default false
    check(safe_to_separate=false),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default (now()+interval '24 hours'),
  constraint qa_preview_ready_valid check(
    status<>'available' or (
      verified_storage_bytes=true and object_sha256 is not null
      and byte_length is not null and expires_at>created_at
    )
  ),
  constraint qa_preview_path_owner check (
    object_path like (recipient_id::text||'/qa-previews/%')
  )
);
create index qa_structured_preview_recipient_time
  on public.qa_structured_preview_staging(recipient_id,created_at desc);
alter table public.qa_structured_preview_staging enable row level security;
create policy "QA preview registry visible only to recipient"
 on public.qa_structured_preview_staging for select
 to authenticated using (recipient_id=(select auth.uid()));
revoke all on public.qa_structured_preview_staging from public,anon,authenticated;
grant select on public.qa_structured_preview_staging to authenticated;
grant select,insert,update,delete on public.qa_structured_preview_staging to service_role;

-- SERVICE ONLY: the user-bound preview is fetched by the caller's JWT via
-- the invoker RPC above. The admin role never fetches plaintext as another
-- member. The reservation rechecks owner and membership before uploading.
create or replace function public.qa_preview_reserve_service(
  p_owner uuid,p_space uuid,p_source_table text,p_source_id uuid
) returns jsonb language plpgsql security invoker set search_path='' as $fn$
declare v_id uuid:=gen_random_uuid(); v_path text; v_exp timestamptz;
begin
  if current_user<>'service_role' then raise exception 'Service role only'; end if;
  if p_owner is null or p_space is null or p_source_id is null
     or p_source_table not in ('shared_trips','tasks') then
    raise exception 'Invalid preview request';
  end if;
  if not exists(select 1 from public.space_members m
     where m.space_id=p_space and m.user_id=p_owner) then
    raise exception 'Private preview owner no longer belongs to source space';
  end if;
  if p_source_table='shared_trips' then
    if not exists(select 1 from public.shared_trips t
       where t.id=p_source_id and t.space_id=p_space
         and t.created_by=p_owner and t.visibility='private') then
       raise exception 'Private trip no longer available';
    end if;
  else
    if not exists(select 1 from public.tasks t
       where t.id=p_source_id and t.space_id=p_space
         and t.created_by=p_owner and t.visibility='private') then
       raise exception 'Private checklist no longer available';
    end if;
  end if;
  perform pg_advisory_xact_lock(21429,hashtext(p_owner::text));
  if (select count(*) from public.qa_structured_preview_staging v
    where v.recipient_id=p_owner
      and v.created_at>now()-interval '24 hours')>=5 then
    raise exception 'QA preview limit reached (5 per 24 hours)';
  end if;
  v_path:=p_owner::text||'/qa-previews/'||v_id::text||'.onespace-preview';
  insert into public.qa_structured_preview_staging(
    id,recipient_id,source_space_id,source_table,source_id,object_path
  ) values(v_id,p_owner,p_space,p_source_table,p_source_id,v_path)
  returning expires_at into v_exp;
  return jsonb_build_object('preview_id',v_id,'object_path',v_path,'expires_at',v_exp);
end $fn$;
revoke all on function public.qa_preview_reserve_service(uuid,uuid,text,uuid)
 from public,anon,authenticated;
grant execute on function public.qa_preview_reserve_service(uuid,uuid,text,uuid)
 to service_role;

create or replace function public.qa_preview_mark_available_service(
  p_id uuid,p_sha256 text,p_byte_length integer
) returns boolean language plpgsql security invoker set search_path='' as $fn$
begin
  if current_user<>'service_role' then raise exception 'Service role only';end if;
  if p_sha256 !~ '^[0-9a-f]{64}$'
     or p_byte_length is null or p_byte_length<1 or p_byte_length>5242880 then
    raise exception 'Invalid verified preview bytes';
  end if;
  update public.qa_structured_preview_staging
     set status='available',object_sha256=p_sha256,
       byte_length=p_byte_length,verified_storage_bytes=true
   where id=p_id and status='pending' and expires_at>now();
  if not found then raise exception 'Preview reservation unavailable'; end if;
  return true;
end $fn$;
revoke all on function public.qa_preview_mark_available_service(uuid,text,integer)
 from public,anon,authenticated;
grant execute on function public.qa_preview_mark_available_service(uuid,text,integer)
 to service_role;

create or replace function public.qa_preview_mark_failed_service(
  p_id uuid
) returns boolean language plpgsql security invoker set search_path='' as $fn$
begin
  if current_user<>'service_role' then raise exception 'Service role only';end if;
  update public.qa_structured_preview_staging set status='failed'
    where id=p_id and status='pending';
  return found;
end $fn$;
revoke all on function public.qa_preview_mark_failed_service(uuid)
 from public,anon,authenticated;
grant execute on function public.qa_preview_mark_failed_service(uuid)
 to service_role;

-- Do not set space archive readiness or any destructive lifecycle flag.
