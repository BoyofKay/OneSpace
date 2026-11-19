-- Read-only, account-scoped audit of the QA shadow migration.
-- Deliberately returns counts, never private snapshots or foreign accounts.
create or replace function private.my_personal_vault_status()
returns jsonb language plpgsql stable security definer
set search_path='' as $$
declare me uuid := auth.uid();
begin
 if me is null then raise exception 'Sign in required'; end if;
 return jsonb_build_object(
   'primary_private_records', (
     select count(*) from public.personal_vault_records
      where owner_id=me and restorable and current_visibility='private'),
   'owned_related_records', (
     select count(*) from public.personal_vault_dependents d
      where d.owner_id=me and exists(
        select 1 from public.personal_vault_records v
        where v.owner_id=d.owner_id and v.source_id=d.parent_id
          and v.source_table=d.parent_table and v.restorable)),
   'private_source_types', (
     select count(distinct source_table) from public.personal_vault_records
      where owner_id=me and restorable),
   'vault_migrated',true,
   'media_exports_verified',false,
   'separation_enabled',false
 );
end $$;
create or replace function public.my_personal_vault_status()
returns jsonb language sql stable security invoker set search_path=''
as $$select private.my_personal_vault_status()$$;
revoke all on function private.my_personal_vault_status(),
 public.my_personal_vault_status() from public,anon;
grant execute on function private.my_personal_vault_status(),
 public.my_personal_vault_status() to authenticated;
