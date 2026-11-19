-- QA 0177: prevent SECURITY DEFINER JSON export from leaking unsent
-- creator-private gesture templates and sender-private schedules to recipient.
-- Media pointers are also excluded using the existing QA structured sanitizer.
-- Does not authorize archive/restore, relationship separation or deletion.
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
  for t in
    select c.table_name,
      string_agg(format('%I = $1', c.column_name), ' or ') as cond
    from information_schema.columns c
    join information_schema.tables x on x.table_schema = c.table_schema
      and x.table_name = c.table_name and x.table_type = 'BASE TABLE'
    where c.table_schema = 'public'
      and c.column_name in ('created_by','user_id','sender_id','owner_id','author_id','recipient_id')
      and c.table_name not in ('account_deletion_requests')
    group by c.table_name order by c.table_name
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
-- Preserve existing authenticated execution only; never allow anon.
revoke all on function public.export_my_data() from public,anon;
grant execute on function public.export_my_data() to authenticated;
