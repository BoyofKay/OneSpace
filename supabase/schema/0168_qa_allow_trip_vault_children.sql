-- QA-only 0168: allow three approved private trip child snapshot types.
-- Preserve the earlier occasion/reminder allowlist and reject all other types.
alter table public.personal_vault_dependents
  drop constraint if exists vault_child_type_allowed;
alter table public.personal_vault_dependents
  add constraint vault_child_type_allowed check (
    (parent_table='occasion_plans' and source_table in (
      'occasion_budget_items','occasion_plan_steps','occasion_proposals'))
    or (parent_table='reminders' and source_table='reminder_recipients')
    or (parent_table='shared_trips' and source_table in (
      'trip_flight_options','trip_items','trip_messages'))
  );
-- Zero private trip children were present before this controlled QA change.
-- Backfill after the new allowlist is active.
do $backfill$
declare trip_record record;
begin
  for trip_record in select id from public.shared_trips where visibility='private' loop
    perform private.qa_sync_private_trip_children(trip_record.id);
  end loop;
end $backfill$;
