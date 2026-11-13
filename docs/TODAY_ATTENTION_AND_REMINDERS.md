# OneSpace — Today attention and in-app reminders
**One Life. Two Places. One Space.**

Today is an action-oriented dashboard, not just a count screen. The new focus feed is included in the same **one-request Home snapshot** (get_home_snapshot_v2(p_today date)), using the signed-in person's local calendar date.

- Overdue shared or privately visible Activities, due-today Activities, high/urgent Activities, and active **reminder components** surface as compact rows.
- Press an item to open its original Activity with the discussion, options, and editing history intact.
- **Snooze for me** (tomorrow/three days/one week) stores a personal preference keyed by the viewer and Activity or reminder component. It never changes the partner's feed or the shared Activity status.
- The Today feed shows upcoming calendar occasions for the next seven days, including date-safe yearly recurrence, and links into the shared calendar.
- Recent Activity discussions deep-link to the specific Activity rather than the general Coordinate landing page.
- The long dashboard totals remain accessible behind an expandable "More shared totals" section.
- Reminders are now addable to any Activity/Option via **Remind us**. The date picker creates a component with creator, timestamp, revision history and 'open' status. A partner may mark a shared reminder **handled**, or reopen it.
- The Remember due list includes reminder components and navigates to the original Activity instead of attempting to open a component UUID as an Activity.
- No push notifications, alarm permissions, background scheduling, emails, or automatic calls are introduced. This release provides **in-app attention/reminders only**.

## Security
The backend is a **SECURITY INVOKER** function. All Activity, component and calendar queries use the signed-in user's existing RLS; source data is not republished to other spaces. Snooze rows have RLS policies requiring the viewer's own user ID and visibility of the underlying Activity. Only the current user can create/update their snoozes.

## Acceptance
1. Create an Activity due tomorrow, open Today on either partner's phone and confirm access.
2. Create a reminder under an Option (e.g., "Ask Gym B about swimming" due Friday); verify it appears in Today and Remember and opens the original Activity.
3. Snooze the reminder for yourself; it disappears for you but stays in your partner's feed.
4. Mark it handled; it disappears from both upcoming feeds while remaining visible with history in the Activity.
5. Add a recurring anniversary; verify the next local calendar occurrence appears only within the next seven days.
6. Verify a private Activity/reminder doesn't appear on an unauthorized partner account.
7. Verify refresh and deep links don't incur additional unrelated network requests.

Device testing and multi-account behavior still need confirmation before production.
