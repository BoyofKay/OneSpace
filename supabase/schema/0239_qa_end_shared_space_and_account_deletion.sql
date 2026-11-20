-- QA 0239: no-archive relationship lifecycle and seven-day account deletion.
--
-- Founder rules (ADR 2026-11-20):
--  * Remove partner / leave / delete space: after a clear warning, all shared
--    content of that couple is deleted at once. Each person keeps their own
--    private content (it lives in their personal space, see 0238) and is
--    unpaired. A future partner never sees old shared content.
--  * Delete account: seven days of grace, cancellable, nothing deleted during
--    the grace. At the deadline: the account, its private content and the
--    current couple's shared content are deleted; the partner keeps their
--    private content and is unpaired.
-- Replaces the archive/"prepare securely" flow and the old keep-shared worker.

-- ---------------------------------------------------------------------------
-- Internal: end one couple space. Deleting the space row cascades to every
-- shared record and its children. Private records are not in this space.
-- ---------------------------------------------------------------------------
create or replace function private.end_couple_space(p_space uuid)
returns jsonb language plpgsql security definer set search_path=''
as $fn$
declare
  t text; n bigint; v_private bigint:=0; v_members int;
begin
  perform 1 from public.spaces
   where id=p_space and personal_owner is null for update;
  if not found then return jsonb_build_object('status','already_ended'); end if;
  select count(*) into v_members from public.space_members where space_id=p_space;

  -- Safety net: never delete a private record by accident. Private records
  -- are routed to personal spaces; if one is still here, stop.
  foreach t in array array['activities','daily_checkins','goals','items_to_sort',
    'memories','occasion_plans','places','saved_contacts','shared_trips',
    'space_counters','notes','tasks','reminders','space_events'] loop
    execute format('select count(*) from public.%I where space_id=$1 and visibility=''private''',t)
      into n using p_space;
    v_private:=v_private+n;
  end loop;
  if v_private>0 then
    raise exception 'Nothing was deleted: % private item(s) are still stored in the shared space. Please contact support.',
      v_private using errcode='P0001';
  end if;

  -- Restrictive link inside occasions; remove before the cascade.
  delete from public.occasion_proposal_items i
   using public.occasion_proposals p, public.occasion_plans o
   where i.proposal_id=p.id and p.plan_id=o.id and o.space_id=p_space;
  -- Retired archive bookkeeping (QA only) that would block the delete.
  if to_regclass('public.qa_archive_job_progress') is not null then
    execute 'delete from public.qa_archive_job_progress where original_space_id=$1' using p_space;
  end if;
  if to_regclass('public.space_lifecycle_jobs') is not null then
    execute 'update public.space_lifecycle_jobs set status=''cancelled'', last_transition_at=now()
               where original_space_id=$1 and status not in (''cancelled'',''completed'')' using p_space;
  end if;

  delete from public.spaces where id=p_space;
  return jsonb_build_object('status','ended','members_unpaired',v_members);
end
$fn$;
revoke all on function private.end_couple_space(uuid) from public,anon,authenticated;

-- ---------------------------------------------------------------------------
-- App: remove partner / leave / delete space. One confirmed call, immediate.
-- p_confirm must be the exact word the warning asked the person to type
-- or tap ("DELETE") so a stray call can never end a relationship.
-- ---------------------------------------------------------------------------
create or replace function public.end_shared_space(p_action text, p_confirm text)
returns jsonb language plpgsql security definer set search_path=''
as $fn$
declare
  v_me uuid:=auth.uid(); v_space uuid; v_owner uuid; v_members int; v_result jsonb;
begin
  if v_me is null then raise exception 'Sign in first' using errcode='42501'; end if;
  if p_action not in ('remove_partner','leave','delete_space') then
    raise exception 'Unknown action' using errcode='22023';
  end if;
  if p_confirm is distinct from 'DELETE' then
    raise exception 'Confirmation required. Nothing was deleted.' using errcode='22023';
  end if;
  v_space:=private.couple_space_id(v_me);
  if v_space is null then
    return jsonb_build_object('status','not_paired');
  end if;
  select created_by into v_owner from public.spaces where id=v_space for update;
  select count(*) into v_members from public.space_members where space_id=v_space;

  if p_action='remove_partner' then
    if v_owner is distinct from v_me then
      raise exception 'Only the person who created the space can remove a partner. You can leave instead.'
        using errcode='42501';
    end if;
    if v_members<2 then
      raise exception 'There is no partner in this space.' using errcode='22023';
    end if;
  elsif p_action='delete_space' then
    if v_owner is distinct from v_me then
      raise exception 'Only the person who created the space can delete it. You can leave instead.'
        using errcode='42501';
    end if;
  elsif p_action='leave' then
    if v_owner = v_me and v_members=2 then
      raise exception 'You created this space. Use Remove partner or Delete space.'
        using errcode='42501';
    end if;
  end if;

  v_result:=private.end_couple_space(v_space);
  return v_result || jsonb_build_object('action',p_action);
end
$fn$;
revoke all on function public.end_shared_space(text,text) from public,anon;
grant execute on function public.end_shared_space(text,text) to authenticated;

-- The old archive-preparation RPC stays disabled; point old builds at the new one.
create or replace function public.request_space_lifecycle_action(p_action text)
returns jsonb language plpgsql set search_path=''
as $fn$
begin
  raise exception 'Please update OneSpace QA. Nothing was changed.';
end
$fn$;

-- ---------------------------------------------------------------------------
-- Account deletion: request, cancel, status.
-- ---------------------------------------------------------------------------
create or replace function public.request_account_deletion()
returns timestamptz language plpgsql security definer set search_path=''
as $fn$
declare v_me uuid:=auth.uid(); v_due timestamptz;
begin
  if v_me is null then raise exception 'Sign in first' using errcode='42501'; end if;
  insert into public.account_deletion_requests(user_id,requested_at,purge_after,cancelled_at,completed_at,last_error)
  values(v_me,now(),now()+interval '7 days',null,null,null)
  on conflict(user_id) do update set
    requested_at=case when public.account_deletion_requests.cancelled_at is null
                       and public.account_deletion_requests.completed_at is null
                      then public.account_deletion_requests.requested_at else now() end,
    purge_after=case when public.account_deletion_requests.cancelled_at is null
                      and public.account_deletion_requests.completed_at is null
                     then public.account_deletion_requests.purge_after else now()+interval '7 days' end,
    cancelled_at=null, completed_at=null, last_error=null
  returning purge_after into v_due;
  return v_due;
end
$fn$;
revoke all on function public.request_account_deletion() from public,anon;
grant execute on function public.request_account_deletion() to authenticated;

create or replace function public.cancel_account_deletion()
returns void language plpgsql security definer set search_path=''
as $fn$
begin
  update public.account_deletion_requests set cancelled_at=now()
   where user_id=auth.uid() and completed_at is null and cancelled_at is null;
end
$fn$;
revoke all on function public.cancel_account_deletion() from public,anon;
grant execute on function public.cancel_account_deletion() to authenticated;

create or replace function public.my_account_deletion()
returns jsonb language sql stable security definer set search_path=''
as $fn$
  select coalesce((
    select jsonb_build_object('scheduled',true,'requested_at',r.requested_at,
                              'delete_after',r.purge_after)
    from public.account_deletion_requests r
    where r.user_id=auth.uid() and r.cancelled_at is null and r.completed_at is null),
    jsonb_build_object('scheduled',false))
$fn$;
revoke all on function public.my_account_deletion() from public,anon;
grant execute on function public.my_account_deletion() to authenticated;

-- ---------------------------------------------------------------------------
-- Deletion worker (service role only, called by the scheduled function).
-- ---------------------------------------------------------------------------
create or replace function public.purge_due_accounts_list()
returns setof uuid language sql security definer set search_path=''
as $fn$
  select r.user_id from public.account_deletion_requests r
  where r.cancelled_at is null and r.completed_at is null and r.purge_after<=now()
  order by r.purge_after limit 20
$fn$;
revoke all on function public.purge_due_accounts_list() from public,anon,authenticated;
grant execute on function public.purge_due_accounts_list() to service_role;

-- Deletes all content of one account; the auth identity itself is deleted by
-- the worker through the Auth admin API right after this succeeds.
-- Idempotent: safe to run again after a partial failure.
create or replace function public.purge_account_content(p_user uuid)
returns jsonb language plpgsql security definer set search_path=''
as $fn$
declare
  v_due boolean; v_couple uuid; v_personal uuid; v_couple_result jsonb:='{}'::jsonb;
begin
  select true into v_due from public.account_deletion_requests
   where user_id=p_user and cancelled_at is null and completed_at is null
     and purge_after<=now()
   for update;
  if not coalesce(v_due,false) then
    return jsonb_build_object('status','not_due');
  end if;

  -- 1. The current couple's shared content goes; the partner becomes unpaired.
  v_couple:=private.couple_space_id(p_user);
  if v_couple is not null then
    v_couple_result:=private.end_couple_space(v_couple);
  end if;
  delete from public.space_members where user_id=p_user;

  -- 2. Their private content: personal space (cascade) ...
  select id into v_personal from public.spaces where personal_owner=p_user;
  if v_personal is not null then
    delete from public.occasion_proposal_items i
     using public.occasion_proposals p, public.occasion_plans o
     where i.proposal_id=p.id and p.plan_id=o.id and o.space_id=v_personal;
    delete from public.spaces where id=v_personal;
  end if;
  -- ... and the account-scoped records (Notes, To-do, Reminders, Calendar).
  delete from public.notes where private_space_id=p_user;
  delete from public.tasks where private_space_id=p_user;
  delete from public.reminders where private_space_id=p_user;
  delete from public.space_events where private_space_id=p_user;
  delete from public.record_action_history where private_space_id=p_user;
  delete from public.space_notifications where private_space_id=p_user or recipient_id=p_user;
  delete from public.user_private_spaces where owner_id=p_user;

  -- 3. Personal settings and devices.
  delete from public.push_devices where user_id=p_user;
  delete from public.personal_days_off where user_id=p_user;
  delete from public.user_attention_snoozes where user_id=p_user;
  delete from public.gesture_message_overrides where owner_id=p_user;

  return jsonb_build_object('status','content_deleted','couple',v_couple_result);
end
$fn$;
revoke all on function public.purge_account_content(uuid) from public,anon,authenticated;
grant execute on function public.purge_account_content(uuid) to service_role;

create or replace function public.mark_account_deleted(p_user uuid, p_error text default null)
returns void language sql security definer set search_path=''
as $fn$
  update public.account_deletion_requests
     set completed_at=case when p_error is null then now() else completed_at end,
         last_error=p_error
   where user_id=p_user and cancelled_at is null and completed_at is null;
$fn$;
revoke all on function public.mark_account_deleted(uuid,text) from public,anon,authenticated;
grant execute on function public.mark_account_deleted(uuid,text) to service_role;

-- Files whose record no longer exists (shared content deleted, account deleted).
-- Already unreadable through Storage policies; the worker removes the bytes.
create or replace function public.orphan_storage_objects(p_limit int default 200)
returns table(bucket_id text, name text)
language sql stable security definer set search_path=''
as $fn$
  select o.bucket_id, o.name from storage.objects o
  where o.created_at < now()-interval '1 hour'
    and (
      (o.bucket_id in ('onespace-activity-media','onespace-activity-voice')
        and not exists(select 1 from public.activities a
                        where a.id::text=(storage.foldername(o.name))[1]))
   or (o.bucket_id='onespace-memory-photos'
        and not exists(select 1 from public.memory_photos p where p.object_path=o.name)
        and not exists(select 1 from public.memories m
                        where m.id=private.memory_id_from_object_path(o.name)))
   or (o.bucket_id='onespace-note-images'
        and not exists(select 1 from public.note_images i where i.object_path=o.name)
        and not exists(select 1 from public.notes n
                        where n.id=private.note_id_from_image_path(o.name)))
   or (o.bucket_id='onespace-trip-documents'
        and not exists(select 1 from public.trip_attachments d where d.object_path=o.name)
        and not exists(select 1 from public.shared_trips t
                        where t.id=private.trip_id_from_storage_path(o.name)))
   or (o.bucket_id='onespace-share-in'
        and not exists(select 1 from auth.users u
                        where u.id::text=(storage.foldername(o.name))[1]))
    )
  limit greatest(1,least(p_limit,1000))
$fn$;
revoke all on function public.orphan_storage_objects(int) from public,anon,authenticated;
grant execute on function public.orphan_storage_objects(int) to service_role;
