-- R46: Retire automatic ("thoughtful ritual") love gestures.
-- Decision 15 Nov 2026: OneSpace keeps manual gestures and private
-- "remind me to send a little love" self-reminders only.
-- Non-destructive: past automated gestures, schedules and templates are kept
-- for history; the sender job stops and no row can trigger a send again.

-- 1. Stop the 5-minute sender job.
select cron.unschedule('onespace-consented-gestures')
where exists (select 1 from cron.job where jobname='onespace-consented-gestures');

-- 2. Disable every saved schedule and recipient consent (history kept).
update public.gesture_schedules set enabled=false, updated_at=now()
 where enabled;
update public.profiles set receive_automatic_gestures=false
 where receive_automatic_gestures;

-- 3. Personal gestures are no longer tied to an automatic moment.
update public.gesture_templates set scheduled_moment=null
 where scheduled_moment is not null;

-- 4. App users can no longer create or re-enable schedules.
revoke insert, update on public.gesture_schedules from authenticated;

comment on function private.send_due_gestures(timestamptz) is
 'RETIRED in R46 (15 Nov 2026). Not scheduled. Kept only for history; do not reschedule.';
comment on table public.gesture_schedules is
 'RETIRED in R46. Read-only history of former automatic rituals.';
