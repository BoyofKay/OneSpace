-- R35: Make occasion preparation reminders genuinely linked, idempotent
-- and annual-event aware. No historical reminders change meaning or status.
alter table public.reminders
 add column if not exists planning_phase text
 check (planning_phase in ('save','research','order','prepare'));
alter table public.reminders
 add column if not exists occasion_instance_on date;
alter table public.reminders
 add constraint reminders_occasion_prep_pair check (
  (planning_phase is null and occasion_instance_on is null)
  or (planning_phase is not null and occasion_instance_on is not null
      and source_kind = 'occasion' and source_id is not null)
 );
-- A user can have one active reminder for each phase / annual occurrence.
-- Other user's independent private reminder is never made visible.
create unique index if not exists reminders_unique_occasion_phase
 on public.reminders(created_by,source_id,occasion_instance_on,planning_phase)
 where source_kind='occasion' and planning_phase is not null
   and archived_at is null;
grant insert(planning_phase,occasion_instance_on)
 on public.reminders to authenticated;
