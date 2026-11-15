# R47 — Reminders for real life

Branch: `r47-reminders-for-real-life` · Date: 15 Nov 2026 · Decisions: D5, D10, D14 in `DECISION_LOG.md` · Spec backlog B-01, B-02, B-03, B-11 (reminders part).

## What changed

| # | Change | Where |
|---|---|---|
| 1 | **Repeating reminders**: Every day · Every weekday · Every week on chosen days · Every month · Every year, "every N", up to 6 times a day, optional end date. Times are kept in the phone's time zone, so daylight-saving changes never move them. The 31st falls back to the month's last day; 29 Feb to 28 Feb. | `0108`, reminder editor |
| 2 | **Done for this time**: on a repeating reminder, Done/Follow-up/Snooze apply to the current occurrence only; the schedule continues. Done up to 12 hours early skips that occurrence. | `respond_to_reminder` |
| 3 | **Missed**: if an occurrence is still unanswered when the next one fires, it is recorded as *Missed* in the reminder history. | dispatcher |
| 4 | **Quiet hours**: a reminder your partner set for you waits until your wake-up time (Profile → Schedule, days off respected) and is recorded as *Held until wake-up*. Your own reminders always fire on time. | dispatcher |
| 5 | **Urgent** (partner reminders only): overrides quiet hours; the alert reads "Urgent: …". | editor, dispatcher |
| 6 | **Linked item closed**: if the linked checklist is completed/cancelled, or the event/occasion is removed or finished, the reminder stops and shows "Linked item closed · no more alerts". | dispatcher |
| 7 | **Partner's local time**: when a reminder is for your partner in another time zone, the editor shows "That's 7:00 AM for Kandice". | editor |
| 8 | **Today**: reminders due for you appear in *Needs attention* (hidden while snoozed) and the next occurrence appears in *Coming up together*; tapping opens the reminder. | `onespace_my_attention`, `onespace_coming_up`, Today |
| 9 | Editor header reads **Add new reminder** / **Edit reminder** (D15). | editor |
| 10 | Removed a dead rule in Needs attention ("urgent" to-dos, which cannot exist). | `onespace_my_attention` |

Database: applied live as migrations `r47_reminders_for_real_life`, `r47_reminder_minute_precision`, `r47_hide_snoozed_reminders_in_attention` (all in `0108`). Additive: existing one-time reminders behave exactly as before. Verified on the live database inside rolled-back transactions: twice-daily schedule, weekdays, every 2 weeks, 31st→28 Feb, 29 Feb→28 Feb, New York daylight-saving, end date, quiet-hours deferral to 07:00, Missed record, Urgent at night, linked checklist cancelled, early Done, snooze hiding from Today.

## Two-phone test script

Before you start: in **Profile → Schedule & days off**, set bedtime and wake-up on **Kandice's** phone (e.g. 23:00 → 07:00). Quiet hours only work when a sleep window is set.

1. **Ahmed:** Remember → Reminders → **+**. The header reads "Add new reminder". Title "Test vitamins", start today in 5 minutes, Repeat = **Every day**, **Add another time** = 5 minutes after the first. Save. The card shows "Every day at … and …".
2. Wait for the first time: the alert arrives; the card shows **Due now**; Today → Needs attention lists it.
3. Tap **Done for this time** → the card shows "Next …" (the second time today). Needs attention no longer lists it.
4. Do not answer the second alert. Tomorrow, after the next alert, open the reminder → Outcome history shows **Missed** for the unanswered time.
5. **Ahmed:** create a reminder for **Partner**, Shared, at a time inside Kandice's sleep window (e.g. 02:00 her time). If her phone is in another time zone, the editor shows "That's … for Kandice". **Do not** tick Urgent. → Kandice gets nothing at 02:00; she gets it at her wake-up time; history shows **Held until wake-up**.
6. Repeat step 5 with **Urgent** on → Kandice is alerted at 02:00 with "Urgent: …".
7. Create a checklist "Test list", then a reminder linked to it (Related item) for 10 minutes later. Cancel the checklist. → No alert arrives; the reminder shows "Linked item closed · no more alerts".
8. Create a weekly reminder: Repeat = Every week on…, tick Mon and Thu, Every **2** weeks, Ends = On a date. The card shows "Every 2 weeks on Mon, Thu at … · until …".
9. Snooze a due reminder by 2 hours → it disappears from Needs attention and comes back when the snooze ends.
10. Today → Coming up together lists your upcoming reminders as "Reminder" / "Repeating reminder"; tapping opens the reminder with its card expanded.
11. Edit an existing one-time reminder created before this update (title only) → it saves and still alerts at its original time.

Clean up afterwards: Archive the test reminders (they stay in history).
