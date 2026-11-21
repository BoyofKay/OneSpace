-- Production finalize: runs at the end of supabase/production/upgrade.sql,
-- inside the same transaction.
--
-- 1. Existing data: Production has items made before private spaces existed.
--    A private item there sits in the couple space (space_id) with
--    visibility='private'. In the new model a private item belongs to its
--    creator's private space (private_space_id = created_by, a row of
--    public.user_private_spaces) and has no couple space, so
--    ending a couple never deletes anyone's private items. Shared items stay
--    where they are. Children (checklist items, comments, photos) follow their
--    parent row and need no change.
-- 2. Switch on leave/remove/delete space and 7-day account deletion (the two
--    gates QA turned on after its acceptance tests).
-- 3. Checks: anything unexpected aborts the whole upgrade.

do $move$
declare
  t text;
  moved int;
  report text := '';
begin
  -- Every account owns a personal space (0243 does this too; harmless again).
  perform private.ensure_personal_space(u.id) from auth.users u where u.deleted_at is null;
  -- Every account has its private namespace (0227 does this too).
  insert into public.user_private_spaces(owner_id)
    select id from auth.users on conflict(owner_id) do nothing;

  for t in
    select c.table_name
      from information_schema.columns c
     where c.table_schema='public' and c.column_name='private_space_id'
       and exists(select 1 from information_schema.columns k where k.table_schema='public'
                  and k.table_name=c.table_name and k.column_name='visibility')
       and exists(select 1 from information_schema.columns k where k.table_schema='public'
                  and k.table_name=c.table_name and k.column_name='created_by')
       and exists(select 1 from information_schema.columns k where k.table_schema='public'
                  and k.table_name=c.table_name and k.column_name='space_id')
       -- Private counters live in the account's personal space (spaces with
       -- personal_owner), not in private_space_id. Production has none today.
       and c.table_name <> 'space_counters'
     order by 1
  loop
    -- Scope guards forbid moving a row between spaces from the app. This is
    -- the one-time move, so they are paused for this table only, inside this
    -- transaction, and switched back on straight after.
    execute format('alter table public.%I disable trigger user', t);
    execute format($u$
      update public.%I r
         set private_space_id = r.created_by,
             space_id = null
       where r.visibility::text = 'private'
         and r.private_space_id is null
         and r.created_by is not null
         and not exists(select 1 from public.spaces s
                         where s.id = r.space_id and s.personal_owner is not null)$u$, t);
    get diagnostics moved = row_count;
    execute format('alter table public.%I enable trigger user', t);
    if moved > 0 then report := report || t || '=' || moved || ' '; end if;
  end loop;
  raise notice 'private items moved to personal spaces: %', coalesce(nullif(report,''),'none');
end
$move$;

-- 2. Lifecycle switches.
insert into private.qa_relationship_v2_gate(id,enabled) values(1,true)
  on conflict (id) do update set enabled=true;
insert into private.qa_account_v2_gate(id,enabled) values(1,true)
  on conflict (id) do update set enabled=true;

-- 3. Checks.
do $check$
declare n int;
begin
  -- No private item may still sit in a couple space.
  select count(*) into n from (
    select 1 from public.activities where visibility::text='private' and private_space_id is null
    union all select 1 from public.notes where visibility::text='private' and private_space_id is null
    union all select 1 from public.tasks where visibility::text='private' and private_space_id is null
    union all select 1 from public.space_events where visibility::text='private' and private_space_id is null
    union all select 1 from public.occasion_plans where visibility::text='private' and private_space_id is null
  ) x;
  if n > 0 then raise exception 'finalize: % private items still in a couple space', n; end if;

  -- Moved items sit in their creator's private space and nowhere else.
  select count(*) into n from (
    select 1 from public.activities where private_space_id is not null and (private_space_id<>created_by or space_id is not null)
    union all select 1 from public.notes where private_space_id is not null and (private_space_id<>created_by or space_id is not null)
    union all select 1 from public.tasks where private_space_id is not null and (private_space_id<>created_by or space_id is not null)
    union all select 1 from public.space_events where private_space_id is not null and (private_space_id<>created_by or space_id is not null)
    union all select 1 from public.occasion_plans where private_space_id is not null and (private_space_id<>created_by or space_id is not null)
  ) x;
  if n > 0 then raise exception 'finalize: % private items in the wrong private space', n; end if;

  -- Every account has exactly one personal space.
  select count(*) into n from auth.users u where u.deleted_at is null
     and not exists(select 1 from public.spaces s where s.personal_owner=u.id);
  if n > 0 then raise exception 'finalize: % accounts without a personal space', n; end if;

  -- Worker schedules point at Production, never at QA.
  select count(*) into n from cron.job where command like '%ugwrpeduzyzrujkizqfo%';
  if n > 0 then raise exception 'finalize: % scheduled jobs still point at QA', n; end if;

  -- The old account purge (keeps shared content) is gone.
  select count(*) into n from cron.job where jobname='onespace-account-purge';
  if n > 0 then raise exception 'finalize: old account purge is still scheduled'; end if;

  -- Key functions the app calls exist.
  if to_regprocedure('public.decline_my_invitation(text)') is null
     or to_regprocedure('public.qa_end_current_relationship(uuid,text,text)') is null
     or to_regprocedure('public.resolve_my_addressed_invitation(text)') is null
     or to_regprocedure('public.create_addressed_invitation(uuid,text,boolean)') is null
     or to_regprocedure('public.qa_request_account_deletion()') is null
     or to_regprocedure('public.qa_find_my_addressed_invitation()') is null
  then raise exception 'finalize: an app function is missing'; end if;
end
$check$;
