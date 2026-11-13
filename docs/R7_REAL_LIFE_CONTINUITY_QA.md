# OneSpace R7 — Real-life continuity

Source: the user's OneSpace project brief, including its examples about
remembering a partner's acquaintances, repeated morning car checklists,
shopping research, reunions, travel, and preparation for celebrations.

## Built in this iteration
- Reusable Checklist: mark any editable checklist reusable; view templates
  through the Reusable filter; choose "Use today" to create a fresh copy.
  Each active item is copied unchecked, original completion remains untouched.
  Copies inherit the source's visibility; a private source remains private.
  A copy references its template and displays the phone's local creation date.
  The server performs the copy in one transaction and checks membership/privacy.
- Countdown Activity component: date-only targets with optional yearly repeat,
  useful for trips, reunions, birthdays and celebrations. Render past dates as
  elapsed time rather than negative numbers; annual Feb 29 falls on Feb 28 in
  non-leap years. Date-only interpretation avoids timezone shifts.
- Today: a secondary, non-blocking countdown fetch shows the nearest
  authorized Activity milestones; tapping one opens its original Activity.
  Countdown data is NOT copied into the Calendar table.
- World People & Contacts: a dedicated quick-create flow for remembering names,
  relationship context, and optional contact information. It creates one
  normal Activity with a Contact component. Shared/private choice follows the
  same existing RLS rules; World indexes those components rather than creating
  a second address book. Original Activity discussion and edits remain available.
- Lists entry now has a standalone Scaffold, matching the prior fixes for
  Calendar, To-dos, and Notes.
- Added pure date/annual countdown regression tests and performance timing
  for the optional Today countdown query.

## Security decisions
- Never duplicate a private checklist into a shared one without consent.
- The clone RPC checks that the caller is a space member and can see the
  template, and is granted only to authenticated users.
- RLS remains the authority for World contacts, Activity components, and
  displayed Today milestones.
- Existing original items, histories, and user data are not deleted.
- User-input dates are validated and the template clone is limited to 150
  active items to prevent accidental runaway duplication.

## Two-device acceptance
1. From phone A, create a shared morning checklist, add three items, mark
   one complete, make the list reusable; confirm B sees the template.
2. From phone B, choose Use today; verify the copied items are all unchecked,
   source template unchanged, and both partners see the new shared copy.
3. Create a private checklist on A and verify B cannot read or copy it.
4. Add an Activity Countdown for a reunion and verify both phones show the
   same local calendar date with appropriate time-remaining labels.
5. Create an annual birthday countdown and test annual rollover.
6. Add a person in World with a relationship note and verify they appear in
   searchable Contacts; private people must remain private.
7. Open Calendar, To-dos, Notes, Lists and World; back gesture should pop
   the child route correctly, and twice-back from Today exits.
8. Test both phones' first frame, startup and page loading times; capture
   exceptions via Copy error details when anything fails.

## R8 priorities / not yet delivered
P0: real-phone validation and performance tracing; correct any remaining
crashes on Calendar/To-dos/Notes and keyboard/navigation regressions.
P1: actionable time-zone-aware alarms and push delivery with quiet-hours
policies and recipient permissions (do not claim current in-app reminders
are OS alarms). Allow early gift/holiday and budget-preparation reminders.
P1: Android native share-in for product links/photos/flight documents, with
a destination chooser that attaches content to the correct Activity or list.
P1: more helpful travel/reunion plans and Calendar linking without duplicate
source-of-truth records.
P2: entertainment lists, watched status, shared reactions, and memories layouts.
P2: per-user themes, Arabic/English UI parity, and iOS test build parity.
Keep emergency-contact OS integration research and shared-data deletion
consent rules as explicit design decisions, not implemented claims.

No public launch until both phones pass the private trial and security review.
