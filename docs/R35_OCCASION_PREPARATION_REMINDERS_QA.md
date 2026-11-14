# R35 — Occasion preparation reminders and cross-module navigation

## Goal and product contract
Connect an occasion's planning milestones to the existing first-class
Reminders feature. Avoid copying the occasion, keeping parallel countdowns,
sending surprise spoilers, or generating notifications before consent.

## Feature
- Occasion details show four milestones based on that occasion's date,
  `saving_lead_days`, and `prep_lead_days`:
  Save money, research options, review ordering deadlines, final prep.
- Uses the *next occurrence* of an annual event (with Feb-29 fallback),
  not the historical original date. Date math remains calendar-based.
- Every suggested milestone can create an ordinary OneSpace Reminder with
  an editable local date/time, initially 9:00 AM local when future.
- Past suggested dates are never inserted as overdue notifications; the
  picker visibly suggests the next 9:00 AM and lets the user choose.
- The new reminder starts **Only me**. If and only if the occasion is
  shared, the creator may explicitly choose **Remind both of us**.
  Nothing is sent until the user taps Create reminder.
- Existing reminder engine owns recipients, outcome/follow-up/snooze,
  due alerts, outbox delivery, push pipeline and source authorization.
- One active phase per creator per occasion occurrence; prevents
  double-taps and duplicates while allowing annual re-planning.
- An existing phase appears as **Reminder already saved** and opens
  its existing record. It can be edited/archived from Reminders.
- Reminders' Open related item navigates directly to the original
  Occasion detail, Calendar item, or Checklist instead of a generic tab.

## Data integrity and privacy
- Additive migration
  `supabase/schema/0099_r35_occasion_preparation_reminders.sql`
  adds optional `planning_phase` and `occasion_instance_on` columns
  to the existing reminders relation. Old reminders remain valid.
- Partial unique index scoped to creator, original occasion, annual
  occurrence and phase, excluding archived records.
- Existing RLS and source visibility validation remain authoritative.
  A private occasion cannot be referenced by a shared reminder.
- Database does **not** auto-create reminders, send surprises, change
  partner settings, or modify stored task/occasion/budget rows.
- Rollback-only RLS integration test 0020 passed on the current paired
  space: duplicate prevented, next-year allowed, partner may independently
  plan, private reminder hidden, and private surprise cannot be revealed.
- No SQL test data persists.

## Automated tests
`test/occasion_preparation_rules_test.dart`
- Four preparation phases and personalized lead time
- Annual rollover including Feb 29
- Expired one-off occasions produce no reminders
- Future-only suggested alerts
- Per-user/per-year duplicate selection.

## Phone acceptance after signed APK
1. Upgrade over the existing preview—do not clear app storage.
2. Open Remember → Occasions & surprises → any active occasion.
3. Review each phase's recommendation, including an already-past
   savings recommendation, without creating an overdue notification.
4. Create a private research reminder, select a specific date/time,
   then reopen the occasion to confirm a saved reminder link.
5. Open it; verify Reminders opens and the original Occasion is linked.
6. If the occasion is shared, explicitly choose Both for another
   reminder. Confirm both partners see it and each retains independent
   completion/snooze outcomes.
7. Confirm a private occasion does not offer a Both option.
8. Test duplicate tap, edit, archive, new annual occurrence and
   timezone differences between the phones.
9. Verify the existing gift comparison, saved proposals, budget,
   Activity links, and shopping statuses remain unchanged.
10. Recheck To-do and Checklists expansion after R34, plus Firebase
    love gestures on both phones.

## Release policy
This is **source-only** until Flutter analyze/tests and signed preview
build succeed. Do not claim physical two-device acceptance until tested.
