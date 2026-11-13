# R11 — Personal Needs Attention & one release per iteration

## Implemented

- Changed .github/workflows/android-dev.yml to dispatch manually or only
  on the explicit release marker update, no auto-build on regular pushes.
  Removed CI's self-generated pubspec.lock commit/push. A failing release
  won't be cancelled merely by a newer commit.
- New invoker-only RPC onespace_my_attention(date) combining:
  * Active Activity deadlines, including overdue, today, tomorrow;
  * Open Activity-component reminders with the same near-term threshold;
  * Open To-dos assigned to the viewer or unassigned/shared;
  * Pending partner check-in requests addressed to the viewer;
  * Unread Activity mentions and replies addressed to the viewer;
  * Explicit undated urgent items and near-term high-priority dated work.
- Discard informational Calendar events; they stay in Coming Up Together.
  Avoid surfacing all high-priority work indefinitely.
- One row per Activity regardless of the number of related reminders/mentions,
  choosing the highest-ranked actionable reason.
- Exclude completed/cancelled/archived items, completed reminders, snoozed
  objects, and partner-assigned To-dos. Existing Activity reminder snoozes
  remain respected. Source-table RLS remains the authority.
- New user_attention_snoozes supports per-user snoozes for Activities, To-dos
  and pending check-in requests. Snoozing does not modify or hide shared data
  on the other partner's phone.
- Action rows navigate to their original Activity, To-dos, or Check-ins.
  Opening an Activity through Needs Attention marks that viewer's unread
  mentions/replies for that Activity as read.
- "Show all actions" actually expands the rest of the list rather than
  opening only the seventh item. Optional attention RPC doesn't block
  Today first paint; reports retry if it fails.
- Notification check-in requests now deep-link to the particular pending
  request's reply form; already-answered requests remain in history.

## Priority design

0 = overdue unfinished obligation
1 = deadline today
2 = direct partner request / unread Activity mention or reply
3 = tomorrow's deadline
4 = urgent work with no date
5 = high-priority work dated within the next three calendar days

A nearby event on the Calendar alone is not an action. The server returns at
most 20 top-ranked unique objects. A user's local calendar date is sent to
RPC as YYYY-MM-DD to avoid UTC date shifts. Do not infer urgency from mood
entries or a partner's personal journal. Any user-specific snooze is local
to that person's account.

## R11 two-Android-phone acceptance

1. Create an overdue Activity, a due-today To-do, tomorrow's reminder, an
   urgent undated Activity, and a high-priority item two days out. Verify
   order and reasons.
2. Create a Calendar-only appointment in five days; ensure it appears in
   Coming Up Together but not Needs Attention.
3. Create two reminder components and multiple mentions in one Activity.
   Verify only one Needs Attention card appears for that Activity.
4. Assign a To-do to partner A; ensure B doesn't get a personal action for
   that assignment. Ensure each partner's private records remain private.
5. Snooze an Activity on A for three days. Confirm it disappears only from
   A's Needs Attention, not B's list or Coordinate.
6. Mark a task completed or Activity cancelled. It must stop appearing.
7. Open an Activity via Needs Attention. Confirm the viewer's unread
   Activity mentions/replies are acknowledged and the list refreshes.
8. Partner A sends B a check-in request. B sees it in Needs Attention and
   can open the exact response form from the notification. Once answered,
   B's pending action disappears.
9. Expand the first six action rows with Show all; verify no actions become
   inaccessible.
10. Repeat performance, Android keyboard, app-back navigation, sleep/day-off
    timing and both-account RLS tests.

## Not included yet

- System-level Android background push notifications (existing notices are
  in-app, under their current permissions).
- Cross-device remote notification delivery while OneSpace is terminated.
- User-configurable thresholds and customized priority coefficients.
- A partner's private personal emotional journal as an alert source.
