-- QA 0304: reconcile the repository with the live QA database (2026-11-20).
--
-- 0243–0303 replay migrations that were applied to QA from unmerged branches.
-- A whitespace-normalised comparison of all 73 functions those files define
-- against live QA found 71 identical. The two below were changed in QA after
-- their source file was written, so the live definitions are recorded here.
-- Neither function is reachable by clients (EXECUTE revoked; gates are off).
--
-- The tail re-asserts the destructive-lifecycle safety state that is live in
-- QA, because 0244 (originally 0239) grants EXECUTE on end_shared_space and
-- would otherwise re-open it on a fresh replay.
-- QA only; never apply to Production.

CREATE OR REPLACE FUNCTION private.end_couple_space(p_space uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  t text; n bigint; v_private bigint:=0; v_members int;
begin
  perform 1 from public.spaces
   where id=p_space and personal_owner is null for update;
  if not found then return jsonb_build_object('status','already_ended'); end if;
  select count(*) into v_members from public.space_members where space_id=p_space;
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
  delete from public.occasion_proposal_items i
   using public.occasion_proposals p, public.occasion_plans o
   where i.proposal_id=p.id and p.plan_id=o.id and o.space_id=p_space;
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
$function$;

CREATE OR REPLACE FUNCTION public.purge_account_content(p_user uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
  v_couple:=private.couple_space_id(p_user);
  if v_couple is not null then
    v_couple_result:=private.end_couple_space(v_couple);
  end if;
  delete from public.space_members where user_id=p_user;
  select id into v_personal from public.spaces where personal_owner=p_user;
  if v_personal is not null then
    delete from public.occasion_proposal_items i
     using public.occasion_proposals p, public.occasion_plans o
     where i.proposal_id=p.id and p.plan_id=o.id and o.space_id=v_personal;
    delete from public.spaces where id=v_personal;
  end if;
  delete from public.notes where private_space_id=p_user;
  delete from public.tasks where private_space_id=p_user;
  delete from public.reminders where private_space_id=p_user;
  delete from public.space_events where private_space_id=p_user;
  delete from public.record_action_history where private_space_id=p_user;
  delete from public.space_notifications where private_space_id=p_user or recipient_id=p_user;
  delete from public.user_private_spaces where owner_id=p_user;
  delete from public.push_devices where user_id=p_user;
  delete from public.personal_days_off where user_id=p_user;
  delete from public.user_attention_snoozes where user_id=p_user;
  delete from public.gesture_message_overrides where owner_id=p_user;
  return jsonb_build_object('status','content_deleted','couple',v_couple_result);
end
$function$;

revoke all on function private.end_couple_space(uuid) from public,anon,authenticated;
revoke all on function public.purge_account_content(uuid) from public,anon,authenticated;

-- Destructive lifecycle stays closed (matches live QA on 2026-11-20).
revoke all on function public.end_shared_space(text,text) from public,anon,authenticated;
revoke all on function public.request_account_deletion() from public,anon,authenticated;
insert into private.qa_relationship_v2_gate(id,enabled) values(1,false)
  on conflict(id) do update set enabled=false;
insert into private.qa_account_v2_gate(id,enabled) values(1,false)
  on conflict(id) do update set enabled=false;
