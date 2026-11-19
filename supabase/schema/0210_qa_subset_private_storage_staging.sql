-- QA 0210: quarantined 24h storage staging of client-side encrypted
-- per-record vault-subset files. NO lifecycle 'ready' archive rows.
-- In private (not API-exposed) schema so the 69-table public source
-- completeness catalog stays strict and unchanged.
create table if not exists private.qa_vault_subset_staging (
 id uuid primary key default gen_random_uuid(),
 owner_id uuid not null references auth.users(id) on delete cascade,
 source_space_id uuid not null references public.spaces(id) on delete cascade,
 object_path text not null unique,
 state text not null default 'pending'
   check (state in ('pending','available','failed')),
 ciphertext_sha256 text
   check (ciphertext_sha256 is null or ciphertext_sha256 ~ '^[0-9a-f]{64}$'),
 byte_length integer
   check (byte_length is null or (byte_length>0 and byte_length<=20971520)),
 verified_storage_bytes boolean not null default false,
 is_verified_archive boolean not null default false
   check (is_verified_archive=false),
 can_restore boolean not null default false check (can_restore=false),
 created_at timestamptz not null default now(),
 expires_at timestamptz not null default (now()+interval '24 hours'),
 constraint qa_subset_available_requires_ciphertext check (
   state<>'available' or
   (verified_storage_bytes and ciphertext_sha256 is not null and byte_length is not null)
 ),
 constraint qa_subset_owner_storage_prefix check (
   object_path=owner_id::text||'/qa-subsets/'||id::text||'.osa'
 )
);
alter table private.qa_vault_subset_staging enable row level security;
revoke all on private.qa_vault_subset_staging from public,anon,authenticated;
create index if not exists qa_subset_staging_expiry_idx
 on private.qa_vault_subset_staging(expires_at,state);
create index if not exists qa_subset_staging_owner_idx
 on private.qa_vault_subset_staging(owner_id,expires_at);

create or replace function public.qa_subset_reserve_service(
 p_owner uuid,p_space uuid)
returns jsonb language plpgsql security definer set search_path='' as $fn$
declare assigned_id uuid:=gen_random_uuid(); object_key text; n int;
begin
 if p_owner is null or p_space is null or not exists(
   select 1 from public.space_members sm
   where sm.user_id=p_owner and sm.space_id=p_space)
   or (select count(*) from public.space_members sm
       where sm.user_id=p_owner)<>1
 then raise exception 'QA subset owner/space mismatch';end if;
 select count(*) into n from private.qa_vault_subset_staging
 where owner_id=p_owner and state in ('pending','available')
   and expires_at>now();
 if n>=3 then raise exception 'QA subset staging quota exceeded';end if;
 object_key:=p_owner::text||'/qa-subsets/'||assigned_id::text||'.osa';
 insert into private.qa_vault_subset_staging(
 id,owner_id,source_space_id,object_path)
 values(assigned_id,p_owner,p_space,object_key);
 return jsonb_build_object('staging_id',assigned_id,
    'object_path',object_key,'is_verified_archive',false,
    'can_restore',false);
end $fn$;
revoke all on function public.qa_subset_reserve_service(uuid,uuid)
 from public,anon,authenticated;
grant execute on function public.qa_subset_reserve_service(uuid,uuid)
 to service_role;

create or replace function public.qa_subset_mark_available_service(
 p_id uuid,p_sha256 text,p_byte_length integer)
returns boolean language plpgsql security definer set search_path='' as $fn$
declare affected int;
begin
 if p_id is null or p_sha256 is null
   or p_sha256 !~ '^[0-9a-f]{64}$'
   or p_byte_length is null or p_byte_length<1 or p_byte_length>20971520
 then raise exception 'QA subset invalid integrity proof';end if;
 update private.qa_vault_subset_staging
 set state='available',ciphertext_sha256=p_sha256,
     byte_length=p_byte_length,verified_storage_bytes=true
 where id=p_id and state='pending' and expires_at>now();
 get diagnostics affected=row_count;
 return affected=1;
end $fn$;
revoke all on function public.qa_subset_mark_available_service(uuid,text,integer)
 from public,anon,authenticated;
grant execute on function public.qa_subset_mark_available_service(uuid,text,integer)
 to service_role;

create or replace function public.qa_subset_lookup_service(
 p_owner uuid,p_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $fn$
declare r private.qa_vault_subset_staging%rowtype;
begin
 if p_owner is null or p_id is null then return 'null'::jsonb;end if;
 select * into r from private.qa_vault_subset_staging
 where id=p_id and owner_id=p_owner and state='available'
 and verified_storage_bytes and not is_verified_archive and not can_restore
 and expires_at>now();
 if not found then return 'null'::jsonb;end if;
 if not exists(select 1 from public.space_members sm
   where sm.user_id=p_owner and sm.space_id=r.source_space_id)
 then return 'null'::jsonb;end if;
 return jsonb_build_object('staging_id',r.id,'owner_id',r.owner_id,
    'source_space_id',r.source_space_id,'object_path',r.object_path,
    'ciphertext_sha256',r.ciphertext_sha256,'byte_length',r.byte_length,
    'is_verified_archive',false,'can_restore',false);
end $fn$;
revoke all on function public.qa_subset_lookup_service(uuid,uuid)
 from public,anon,authenticated;
grant execute on function public.qa_subset_lookup_service(uuid,uuid)
 to service_role;

create or replace function public.qa_subset_mark_failed_service(p_id uuid)
returns boolean language plpgsql security definer set search_path='' as $fn$
declare affected int;
begin
 update private.qa_vault_subset_staging set state='failed'
 where id=p_id and state='pending';
 get diagnostics affected=row_count;
 return affected=1;
end $fn$;
revoke all on function public.qa_subset_mark_failed_service(uuid)
 from public,anon,authenticated;
grant execute on function public.qa_subset_mark_failed_service(uuid)
 to service_role;

create or replace function public.qa_subset_due_purge_service()
returns jsonb language sql stable security definer set search_path='' as $fn$
 select coalesce(jsonb_agg(jsonb_build_object(
    'staging_id',d.id,'object_path',d.object_path)
    order by d.created_at),'[]'::jsonb)
 from (
   select id,object_path,created_at
   from private.qa_vault_subset_staging
   where state='failed' or expires_at<=now()
      or (state='pending' and created_at<now()-interval '10 minutes')
   order by created_at limit 200
 ) d
$fn$;
revoke all on function public.qa_subset_due_purge_service()
 from public,anon,authenticated;
grant execute on function public.qa_subset_due_purge_service()
 to service_role;

create or replace function public.qa_subset_finish_purge_service(p_id uuid)
returns boolean language plpgsql security definer set search_path='' as $fn$
declare affected int;
begin
 delete from private.qa_vault_subset_staging
 where id=p_id and (state='failed' or expires_at<=now()
    or (state='pending' and created_at<now()-interval '10 minutes'));
 get diagnostics affected=row_count;
 return affected=1;
end $fn$;
revoke all on function public.qa_subset_finish_purge_service(uuid)
 from public,anon,authenticated;
grant execute on function public.qa_subset_finish_purge_service(uuid)
 to service_role;
