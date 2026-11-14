-- R36: personal self-reminders to send an affectionate gesture.
-- These never send a gesture and can never become shared reminders.
alter table public.reminders add column reminder_intent text
 check (reminder_intent in ('love_gesture'));
alter table public.reminders add column reminder_gesture_kind text
 check(reminder_gesture_kind in (
  'any','hug','miss_you','thinking','smile','morning','goodnight',
  'proud','support','thanks','lucky','miss_together','miss_home',
  'miss_kids','miss_pets'
 ));
alter table public.reminders add constraint reminders_love_prompt_privacy check (
 (reminder_intent is null and reminder_gesture_kind is null)
 or (reminder_intent = 'love_gesture'
  and reminder_gesture_kind is not null
  and visibility='private' and audience='me'
  and source_kind is null and source_id is null)
);
grant insert(reminder_intent,reminder_gesture_kind) on public.reminders
 to authenticated;
-- Stops concurrent duplicate taps from creating exactly the same prompt.
create unique index reminders_love_prompt_exact_time_unique
 on public.reminders(created_by,due_at,reminder_intent,reminder_gesture_kind)
 where reminder_intent='love_gesture' and archived_at is null;
