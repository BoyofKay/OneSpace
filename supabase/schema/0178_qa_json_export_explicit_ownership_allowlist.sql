-- QA 0178: fail-closed, frozen JSON export table/field allowlist.
-- Current 63 tables preserve existing intended export coverage, with 0177
-- creator/sender-only protection and structured media stripping.
do $guard$
declare n int;
begin
  select count(*) into n from (
    select distinct c.table_name from information_schema.columns c
    join information_schema.tables t on t.table_schema=c.table_schema
      and t.table_name=c.table_name and t.table_type='BASE TABLE'
    where c.table_schema='public'
      and c.column_name in ('created_by','user_id','sender_id','owner_id','author_id','recipient_id')
      and c.table_name<>'account_deletion_requests'
  ) eligible;
  if n<>63 then raise exception 'QA export schema changed: re-review static table/ownership allowlist';end if;
end $guard$;
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
revoke all on function public.export_my_data() from public,anon;
grant execute on function public.export_my_data() to authenticated;
