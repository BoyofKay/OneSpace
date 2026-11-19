-- QA archive lifecycle groundwork. No existing rows are modified.
-- Archive contents will be created only by a future verified export worker.
-- An automatic app-private copy never marks an archive downloaded.
create table if not exists public.space_archives (
 id uuid primary key default gen_random_uuid(),
 old_space_id uuid not null, -- deliberately not FK: relationship can retire
 recipient_id uuid not null references auth.users(id),
 archive_kind text not null check(archive_kind in ('private','shared')),
 status text not null default 'pending'
   check(status in ('pending','ready','purge_due','purged','failed')),
 archive_format text not null default 'onespace-v2',
 created_at timestamptz not null default now(),
 ready_at timestamptz,
 expires_at timestamptz,
 encrypted_object_path text unique,
 ciphertext_sha256 text,
 byte_length bigint check(byte_length is null or byte_length > 0),
 explicit_download_confirmed_at timestamptz,
 purged_at timestamptz,
 last_error text check(last_error is null or length(last_error)<=500),
 constraint ready_archives_complete check (
   status not in ('ready','purge_due','purged') or
   (ready_at is not null and expires_at is not null and
    encrypted_object_path is not null and
    ciphertext_sha256 ~ '^[0-9a-f]{64}$' and byte_length>0)),
 constraint expire_after_ready check (
   expires_at is null or
   (ready_at is not null and expires_at = ready_at+interval '30 days'))
);
create index if not exists space_archives_by_recipient
 on public.space_archives(recipient_id,created_at desc);
create index if not exists space_archives_due_cleanup
 on public.space_archives(expires_at,explicit_download_confirmed_at)
 where status in ('ready','purge_due');
alter table public.space_archives enable row level security;
revoke all on public.space_archives from public,anon,authenticated;
grant select on public.space_archives to authenticated;
create policy "Read only my archive metadata"
 on public.space_archives for select to authenticated
 using(recipient_id=(select auth.uid()));
-- Audit records do NOT include any stored passwords, recovery keys, or files.

insert into storage.buckets(id,name,public,file_size_limit)
 values('onespace-archives','onespace-archives',false,52428800)
 on conflict(id) do nothing;
-- No authenticated storage.objects policies for this bucket: only privileged
-- archive service downloads can be authorized with user identity checks.

-- This RPC is exclusively for the client after an EXPLICIT Save/Download to
-- a user-selected EXTERNAL location completes and hash verification passes.
-- It is never called on background app-private download.
create or replace function private.confirm_external_archive_save(
 p_archive_id uuid,p_sha256 text)
returns boolean language plpgsql security definer set search_path=''
as $$
declare me uuid := auth.uid(); row_found public.space_archives%rowtype;
begin
 if me is null then raise exception 'Sign in required'; end if;
 select * into row_found from public.space_archives
 where id=p_archive_id and recipient_id=me for update;
 if not found then raise exception 'Archive not found'; end if;
 if row_found.status='purge_due' and row_found.explicit_download_confirmed_at is not null then
   return true;
 end if;
 if row_found.status<>'ready' or row_found.expires_at<=now() then
   raise exception 'Archive is no longer available';
 end if;
 if p_sha256 is null or p_sha256<>row_found.ciphertext_sha256 then
   raise exception 'Archive file failed verification';
 end if;
 update public.space_archives set explicit_download_confirmed_at=now(),
   status='purge_due'
 where id=p_archive_id;
 return true;
end $$;

create or replace function public.confirm_external_archive_save(
 p_archive_id uuid,p_sha256 text
) returns boolean language sql security invoker set search_path=''
as $$select private.confirm_external_archive_save(p_archive_id,p_sha256)$$;
revoke all on function public.confirm_external_archive_save(uuid,text)
 from public,anon;
revoke all on function private.confirm_external_archive_save(uuid,text)
 from public,anon;
grant execute on function public.confirm_external_archive_save(uuid,text)
 to authenticated;
grant execute on function private.confirm_external_archive_save(uuid,text)
 to authenticated;

-- Service-only maintenance RPC for the archive janitor. An automatic
-- app-private download is not represented in these predicates.
create or replace function public.archives_due_for_purge_service()
returns table(archive_id uuid,object_path text)
language plpgsql security invoker set search_path=''
as $$
begin
 if current_user<>'service_role' then raise exception 'Service role only'; end if;
 return query
  select a.id,a.encrypted_object_path from public.space_archives a
  where a.status in ('ready','purge_due')
    and (a.explicit_download_confirmed_at is not null
         or a.expires_at<=now())
  order by a.created_at limit 100;
end $$;

create or replace function public.finish_archive_purge_service(
 p_archive_id uuid,p_error text default null
) returns boolean language plpgsql security invoker set search_path=''
as $$
begin
 if current_user<>'service_role' then raise exception 'Service role only'; end if;
 update public.space_archives
 set status=case when p_error is null then 'purged' else 'purge_due' end,
     purged_at=case when p_error is null then now() else null end,
     last_error=case when p_error is null then null else left(p_error,500) end
 where id=p_archive_id and status in ('ready','purge_due')
   and (explicit_download_confirmed_at is not null or expires_at<=now());
 return found;
end $$;
revoke all on function public.archives_due_for_purge_service(),
 public.finish_archive_purge_service(uuid,text)
 from public,anon,authenticated;
grant execute on function public.archives_due_for_purge_service(),
 public.finish_archive_purge_service(uuid,text) to service_role;
grant select,insert,update on public.space_archives to service_role;
