-- QA 0228: forward-compatible ownership columns on eligible content ROOTS.
-- Additive schema only: existing records, policy, triggers, and app routing
-- remain untouched. Private-only records cannot be created under new scope
-- until explicitly authorized RLS/trigger and unified screen cutover.
do $expand$
declare r record; kinds integer;
begin
 select count(*) into kinds from private.qa_archive_table_policy p
 where p.relation_kind='root' and p.approved
   and p.disposition in ('private_shared','owner_private');
 if kinds<>22 then
   raise exception 'Unexpected eligible root families: %',kinds;
 end if;
 for r in
  select p.source_table from private.qa_archive_table_policy p
  where p.relation_kind='root' and p.approved
    and p.disposition in ('private_shared','owner_private')
  order by p.source_table
 loop
  if not exists(select 1 from information_schema.columns c
      where c.table_schema='public' and c.table_name=r.source_table
        and c.column_name='space_id') then
    raise exception 'Eligible root has no legacy space ID: %',r.source_table;
  end if;
  execute format('alter table public.%I add column if not exists private_space_id uuid',
    r.source_table);
  execute format('alter table public.%I alter column space_id drop not null',
    r.source_table);
  if not exists(select 1 from pg_constraint c
    where c.conrelid=format('public.%I',r.source_table)::regclass
      and c.conname=r.source_table||'_private_space_fk') then
    execute format('alter table public.%I add constraint %I foreign key (private_space_id) references public.user_private_spaces(owner_id) NOT VALID',
      r.source_table,r.source_table||'_private_space_fk');
  end if;
  if not exists(select 1 from pg_constraint c
    where c.conrelid=format('public.%I',r.source_table)::regclass
      and c.conname=r.source_table||'_exactly_one_space_scope') then
    execute format('alter table public.%I add constraint %I check ((space_id is not null) <> (private_space_id is not null)) NOT VALID',
      r.source_table,r.source_table||'_exactly_one_space_scope');
  end if;
  if exists(select 1 from information_schema.columns c
    where c.table_schema='public' and c.table_name=r.source_table
      and c.column_name='visibility') then
    if not exists(select 1 from pg_constraint c
      where c.conrelid=format('public.%I',r.source_table)::regclass
        and c.conname=r.source_table||'_private_scope_visibility') then
      execute format('alter table public.%I add constraint %I check (private_space_id is null or visibility=''private'') NOT VALID',
        r.source_table,r.source_table||'_private_scope_visibility');
    end if;
  end if;
  if exists(select 1 from information_schema.columns c
    where c.table_schema='public' and c.table_name=r.source_table
      and c.column_name='created_by') then
    if not exists(select 1 from pg_constraint c
      where c.conrelid=format('public.%I',r.source_table)::regclass
        and c.conname=r.source_table||'_private_scope_creator') then
      execute format('alter table public.%I add constraint %I check (private_space_id is null or private_space_id=created_by) NOT VALID',
        r.source_table,r.source_table||'_private_scope_creator');
    end if;
  end if;
  execute format('create index if not exists %I on public.%I(private_space_id) where private_space_id is not null',
    r.source_table||'_private_space_idx',r.source_table);
 end loop;
end $expand$;

-- Do not claim private records have migrated until all 22 families and their
-- dependents are moved, RLS and triggers are updated, and all clients use the
-- single unified private/shared feed. Prior schema uses remain supported.
