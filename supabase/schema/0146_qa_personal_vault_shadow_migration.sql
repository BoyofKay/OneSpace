-- QA-only additive personal vault migration. Source rows are NOT deleted or modified.
-- Do not route existing screens through this table until verified cutover.
create table if not exists public.personal_vault_records(
 owner_id uuid not null references auth.users(id) on delete cascade,
 source_table text not null,
 source_id uuid not null,
 source_space_id uuid,
 original_visibility text not null default 'private' check(original_visibility='private'),
 current_visibility text not null default 'private',
 restorable boolean not null default true,
 snapshot jsonb not null,
 captured_at timestamptz not null default now(),
 last_mirrored_at timestamptz not null default now(),
 primary key(owner_id,source_table,source_id),
 constraint personal_vault_source_allowed check(source_table in
 ('activities','daily_checkins','goals','items_to_sort','memories',
 'notes','occasion_plans','places','reminders','saved_contacts',
 'shared_trips','space_counters','space_events','tasks'))
);
create index if not exists personal_vault_by_owner
 on public.personal_vault_records(owner_id,restorable,source_table);
alter table public.personal_vault_records enable row level security;
revoke all on public.personal_vault_records from public,anon,authenticated;
-- Mirror is an internal trigger. Clients may neither read nor overwrite
-- unsanitized raw snapshots; later restoration must strip old shared links.
create or replace function private.mirror_personal_vault_record()
returns trigger language plpgsql security definer
set search_path='' as $$
begin
 if tg_table_schema<>'public' or tg_table_name not in
  ('activities','daily_checkins','goals','items_to_sort','memories',
   'notes','occasion_plans','places','reminders','saved_contacts',
   'shared_trips','space_counters','space_events','tasks') then
  raise exception 'Unexpected vault source';
 end if;
 if new.created_by is null then return new; end if;
 if new.visibility='private' then
   insert into public.personal_vault_records
     (owner_id,source_table,source_id,source_space_id,
      original_visibility,current_visibility,restorable,snapshot)
   values(new.created_by,tg_table_name,new.id,new.space_id,
     'private','private',true,to_jsonb(new))
   on conflict(owner_id,source_table,source_id) do update set
     source_space_id=excluded.source_space_id,
     current_visibility='private',restorable=true,
     snapshot=excluded.snapshot,last_mirrored_at=now();
 elsif tg_op='UPDATE' and old.visibility='private'
    and old.created_by is not null then
   -- If a private item becomes shared, it must never be restored privately
   -- from a stale vault snapshot.
   update public.personal_vault_records set
     current_visibility=new.visibility,restorable=false,
     last_mirrored_at=now()
   where owner_id=old.created_by and source_table=tg_table_name
     and source_id=old.id;
 end if;
 return new;
end $$;
revoke execute on function private.mirror_personal_vault_record()
 from public,anon,authenticated;

-- Lock the source schema for the duration of the backfill and trigger setup;
-- PostgreSQL's migration transaction keeps this consistent.
do $$
declare tab text;
begin
 foreach tab in array array[
 'activities','daily_checkins','goals','items_to_sort','memories',
 'notes','occasion_plans','places','reminders','saved_contacts',
 'shared_trips','space_counters','space_events','tasks']
 loop
   execute format('drop trigger if exists qa_personal_vault_mirror on public.%I',tab);
   execute format('create trigger qa_personal_vault_mirror after insert or update on public.%I for each row execute function private.mirror_personal_vault_record()',tab);
   execute format(
    'insert into public.personal_vault_records
     (owner_id,source_table,source_id,source_space_id,
      original_visibility,current_visibility,restorable,snapshot)
     select created_by,%L,id,space_id,''private'',''private'',true,to_jsonb(t)
     from public.%I t
     where visibility=''private'' and created_by is not null
     on conflict(owner_id,source_table,source_id) do update
      set snapshot=excluded.snapshot,
          source_space_id=excluded.source_space_id,
          current_visibility=''private'',restorable=true,
          last_mirrored_at=now()',tab,tab);
 end loop;
end $$;

-- The vault is intentionally inaccessible through the client Data API.
-- A separately authorized, redacted service/export API will be required.
