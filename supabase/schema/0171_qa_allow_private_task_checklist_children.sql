-- QA 0171: permit only task checklist structured children in personal vault.
-- Existing occasion, reminder and trip child allowlist remains unchanged.
alter table public.personal_vault_dependents drop constraint vault_child_type_allowed;
alter table public.personal_vault_dependents add constraint vault_child_type_allowed check (
 (parent_table='occasion_plans' and source_table in
  ('occasion_budget_items','occasion_plan_steps','occasion_proposals'))
 or (parent_table='reminders' and source_table='reminder_recipients')
 or (parent_table='shared_trips' and source_table in
  ('trip_flight_options','trip_items','trip_messages'))
 or (parent_table='tasks' and source_table in
  ('task_checklist_items','task_checklist_checks'))
);
