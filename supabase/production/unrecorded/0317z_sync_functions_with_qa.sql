-- Production upgrade only: make 7 functions identical to the versions QA runs
-- (read from QA with pg_get_functiondef on 2026-11-21). They differ after the
-- file replay because QA received later fixes in the SQL editor, or because
-- 0220 (Production prelaunch gate) wrote Production-only versions that QA
-- replaced since. QA's versions are the ones the app was tested against.
-- CREATE OR REPLACE keeps each function's existing grants.

CREATE OR REPLACE FUNCTION public.decline_my_invitation(p_token text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare me uuid:=auth.uid(); my_email text; inv record;
begin
 select lower(u.email) into my_email from auth.users u where u.id=me;
 if me is null or my_email is null then
  raise exception 'Sign in required' using errcode='42501';
 end if;
 select i.id,i.invited_by,i.invited_email into inv from public.space_invitations i
  where i.token=p_token and i.accepted_at is null and i.revoked_at is null
    and i.expires_at>now()
  for update;
 if not found then return; end if;
 if lower(coalesce(inv.invited_email,'')) is distinct from my_email then
  raise exception 'This invitation belongs to another email address' using errcode='42501';
 end if;
 update public.space_invitations set revoked_at=now() where id=inv.id;
 insert into public.account_notices(user_id,kind,title,body) values(inv.invited_by,
  'invitation_declined',private.qa_first_name(me,'Your invitee')||' declined your invitation',
  'You can invite them again or invite someone else from My Space.');
end $function$
;

CREATE OR REPLACE FUNCTION public.log_client_error(p_error text, p_stack text, p_context text, p_app_version text, p_platform text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare me uuid:=coalesce(
 nullif(pg_catalog.current_setting('request.jwt.claim.sub',true),''),
 nullif(pg_catalog.current_setting('request.jwt.claims',true),'')::jsonb->>'sub')::uuid;
begin
 if me is null then return; end if;
 if pg_catalog.octet_length(coalesce(p_error,''))>16000 or pg_catalog.octet_length(coalesce(p_stack,''))>32000 then return; end if;
 if not pg_catalog.pg_try_advisory_xact_lock(21427,9112) then return; end if;
 if (select count(*) from public.client_errors where user_id=me and created_at>pg_catalog.now()-interval '1 hour')>=40
 or (select count(*) from public.client_errors where created_at>pg_catalog.now()-interval '1 hour')>=500 then return; end if;
 insert into public.client_errors(user_id,error,stack,context,app_version,platform)
 values(me,left(coalesce(p_error,'?'),1000),left(p_stack,4000),left(p_context,300),left(p_app_version,40),left(p_platform,20));
end $function$
;

CREATE OR REPLACE FUNCTION public.sealed_letters()
 RETURNS TABLE(id uuid, author_id uuid, open_on date, sent_at timestamp with time zone)
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  select l.id,l.author_id,l.open_on,l.sent_at
  from public.couple_letters l
  where false
$function$
;

CREATE OR REPLACE FUNCTION public.end_shared_space(p_action text, p_confirm text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$
;

CREATE OR REPLACE FUNCTION public.export_my_data()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  me uuid := auth.uid();
  result jsonb;
  t record;
  rows jsonb;
begin
  if me is null then raise exception 'Sign in first'; end if;
  result := jsonb_build_object(
    'exported_at', now(),
    'format', 'OneSpace export v1',
    'note', 'Everything you created or received in OneSpace. Shared items your partner created are not included.',
    'profile', (select private.qa_structured_value(to_jsonb(p)) from public.profiles p where p.id = me));
  -- Explicit 63-table policy, reviewed at QA migration 0178.
  -- SECURITY DEFINER bypasses RLS. Future tables or added recipient fields
  -- are not implicitly exportable merely because they have matching columns.
  for t in
    select approved.table_name,approved.cond from (
      select unnest(array['activities','activity_components','activity_decisions','daily_checkins','goals','item_links','items_to_sort','memories','memory_photos','note_images','note_references','notes','occasion_budget_items','occasion_plan_steps','occasion_plans','occasion_proposals','place_visits','places','reminders','saved_contacts','scrapbook_pages','shared_experience_comments','shared_experiences','shared_trips','space_counters','space_events','space_special_dates','space_tags','spaces','task_checklist_items','tasks','trip_attachments','trip_flight_options','trip_items','trip_messages']) as table_name,
             'created_by = $1'::text as cond
      union all
      select unnest(array['activity_attention_snoozes','activity_component_reactions','client_errors','partner_checkin_acknowledgements','personal_days_off','push_devices','shared_experience_interests','shared_experience_reviews','space_lifecycle_job_participants','space_members','support_requests','task_checklist_checks','user_attention_snoozes']) as table_name,
             'user_id = $1'::text as cond
      union all
      select unnest(array['activity_comments','couple_letters']) as table_name,
             'author_id = $1'::text as cond
      union all
      select unnest(array['calendar_partner_reminders','partner_checkin_requests','partner_gestures']) as table_name,
             'recipient_id = $1 or sender_id = $1'::text as cond
      union all
      select unnest(array['gesture_message_overrides','personal_vault_dependents','personal_vault_records','space_media_inventory']) as table_name,
             'owner_id = $1'::text as cond
      union all
      select unnest(array['gesture_schedules']) as table_name,
             'sender_id = $1'::text as cond
      union all
      select unnest(array['gesture_templates']) as table_name,
             'creator_id = $1'::text as cond
      union all
      select unnest(array['reminder_actions','reminder_recipients','space_archives','space_notifications']) as table_name,
             'recipient_id = $1'::text as cond
    ) approved order by approved.table_name
  loop
    -- Two owner-only gesture tables also have a recipient_id field.
    -- That recipient is NOT authorized to export an unsent template or
    -- another person's private scheduling preferences. This function
    -- bypasses RLS, so it must never rely on the generic recipient match.
    if t.table_name='gesture_templates' then
      select coalesce(jsonb_agg(private.qa_structured_value(to_jsonb(r))), '[]'::jsonb)
        into rows from public.gesture_templates r where r.creator_id=me;
    elsif t.table_name='gesture_schedules' then
      select coalesce(jsonb_agg(private.qa_structured_value(to_jsonb(r))), '[]'::jsonb)
        into rows from public.gesture_schedules r where r.sender_id=me;
    else
      execute format(
        'select coalesce(jsonb_agg(private.qa_structured_value(to_jsonb(r))), ''[]''::jsonb)
         from public.%I r where %s',t.table_name,t.cond)
        into rows using me;
    end if;
    if t.table_name = 'push_devices' then
      rows := (select coalesce(jsonb_agg(e - 'token' - 'fcm_token'), '[]'::jsonb) from jsonb_array_elements(rows) e);
    end if;
    if jsonb_array_length(rows) > 0 then
      result := result || jsonb_build_object(t.table_name, rows);
    end if;
  end loop;
  return result;
end $function$
;

CREATE OR REPLACE FUNCTION private.qa_close_relationship_v2(p_space uuid, p_action text, p_confirmation text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare me uuid:=auth.uid(); owner_id uuid; guest uuid; members int;
 owner_name text; guest_name text; by_deletion boolean; result jsonb;
 kept uuid; new_space uuid;
 safe constant text:=' Shared items were removed. Private items are safe.';
begin
 select s.created_by into owner_id from public.spaces s where s.id=p_space;
 select count(*) into members from public.space_members m where m.space_id=p_space;
 select m.user_id into guest from public.space_members m
  where m.space_id=p_space and m.user_id<>owner_id limit 1;

 result:=private.qa_close_relationship_v2_core(p_space,p_action,p_confirmation);

 if members<>2 or guest is null or owner_id is null then return result; end if;
 owner_name:=private.qa_first_name(owner_id,'Your partner');
 guest_name:=private.qa_first_name(guest,'Your partner');
 by_deletion:=exists(select 1 from public.account_deletion_requests r
   where r.user_id=me and r.cancelled_at is null and r.completed_at is null
     and r.purge_after<=now());

 if by_deletion then
  if me=guest then
   kept:=owner_id;
   insert into public.account_notices(user_id,kind,title,body) values(owner_id,
    'partner_deleted_account',guest_name||' deleted their account',
    'Your space is still here, ready for a new partner.'||safe);
  else
   insert into public.account_notices(user_id,kind,title,body) values(guest,
    'partner_deleted_account',owner_name||' deleted their account',
    'Their shared space was closed. You can join a partner, invite one, or create your own space.'||safe);
  end if;
 elsif p_action='leave_space' then
  kept:=owner_id;
  insert into public.account_notices(user_id,kind,title,body) values
   (owner_id,'partner_left',guest_name||' left your space',
    'Your space is still here, ready for a new partner.'||safe),
   (guest,'you_left','You left '||owner_name||'''s space',
    'You can join a partner, invite one, or create your own space.'||safe);
 elsif p_action='remove_partner' then
  kept:=owner_id;
  insert into public.account_notices(user_id,kind,title,body) values
   (owner_id,'you_removed_partner','You removed '||guest_name,
    'Your space is still here, ready for a new partner.'||safe),
   (guest,'partner_removed_you',owner_name||' removed you from their space',
    'You can join a partner, invite one, or create your own space.'||safe);
 elsif p_action='delete_space' then
  insert into public.account_notices(user_id,kind,title,body) values
   (owner_id,'you_deleted_space','You deleted your shared space',
    'You can invite a partner, join one, or create a new space.'||safe),
   (guest,'space_deleted',owner_name||' deleted the shared space',
    'You can join a partner, invite one, or create your own space.'||safe);
 end if;

 if kept is not null and not private.qa_account_pending_delete(kept)
    and not exists(select 1 from public.space_members m join public.spaces s on s.id=m.space_id
                   where m.user_id=kept and s.personal_owner is null) then
  insert into public.spaces(created_by) values(kept) returning id into new_space;
  insert into public.space_members(space_id,user_id) values(new_space,kept);
  result:=result||jsonb_build_object('owner_space_kept',new_space);
 end if;
 return result;
end $function$
;

CREATE OR REPLACE FUNCTION public.submit_public_support(p_kind text, p_subject text, p_message text, p_reply_email text, p_app_version text, p_platform text, p_locale text, p_diagnostics text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_kind text:=lower(btrim(coalesce(p_kind,'')));
        v_subject text:=btrim(coalesce(p_subject,''));
        v_message text:=btrim(coalesce(p_message,''));
        v_email text:=lower(btrim(coalesce(p_reply_email,'')));
begin
 if v_kind not in ('contact','account','issue','complaint')
    or char_length(v_subject)>160
    or char_length(v_message) not between 1 and 8000
    or char_length(v_email) not between 5 and 254
    or v_email !~ '^[^[:space:]@]+@[^[:space:]@]+[.][^[:space:]@]+$'
    or char_length(coalesce(p_app_version,''))>40
    or char_length(coalesce(p_platform,''))>32
    or char_length(coalesce(p_locale,''))>16
    or char_length(coalesce(p_diagnostics,''))>4000
 then raise exception 'Invalid support request' using errcode='22023'; end if;
 if not pg_catalog.pg_try_advisory_xact_lock(21427,9111) then
   raise exception 'Support is busy. Please try again shortly.'; end if;
 if (select count(*) from public.public_support_requests where created_at>pg_catalog.now()-interval '1 hour')>=30
 or (select count(*) from public.public_support_requests where lower(reply_email)=v_email and created_at>pg_catalog.now()-interval '1 hour')>=3
 then raise exception 'Too many messages. Please try again later.'; end if;
 insert into public.public_support_requests(kind,subject,message,reply_email,app_version,platform,locale,diagnostics)
 values(v_kind,v_subject,v_message,v_email,p_app_version,p_platform,p_locale,p_diagnostics);
end $function$
;
