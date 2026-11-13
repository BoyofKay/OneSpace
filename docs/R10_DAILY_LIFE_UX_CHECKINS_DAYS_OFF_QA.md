# OneSpace R10 — partner-reviewed UX and shared-life business logic

## Scope implemented
- AppBar: compact OneSpace heading, notifications bell, second-from-right
  overflow (Settings, Search, Language), and separate Profile last.
- Relationship Settings: Together / Living apart segmented choice; independent
  Last Met and Next Meeting date pickers with explicit clear; changes saved
  for both partners. Dashboard counts no longer depend on clock/weather.
- Today: Living together shows a warm placeholder. Meeting date counters
  remain independently visible. Weather/clocks stay hidden when together.
  All three Today accordions share spacing and show collapsed hints.
- Recent Discussions: latest message per Activity, with a count of recent
  comments rather than repeated Activity cards.
- Coming Up Together: a new invoker-only RLS-filtered 7-day source aggregator
  includes Calendar events, open To-dos, active Activity due dates, dated
  Activity components, and yearly Calendar occurrences.
  It does not duplicate stored events. A separate optional read avoids
  blocking the first dashboard paint.
- Saved people and contacts moved from World into Remember.
- Daily check-ins: record your own mood 1–5, thoughts, gratitude and
  private/shared choice; private journals do not notify the partner.
  Separate partner check-in request and response, with rating, thoughts,
  something to discuss, sent/responded timestamps and two-person-only RLS.
  New shared journals/requests/replies create in-app notifications and open
  the Check-ins screen when tapped.
- Love gestures: new themed preset categories—thank you, lucky to have you,
  miss us together, miss home, miss kids, miss furry ones. Settings opens a
  management-only gesture screen rather than sending screen, with creator-
  owned editing and removal; thoughtful ritual controls appear in the same
  area. Removed duplicated automatic-consent settings link.
- Days off: each partner can add and maintain personal day-off dates,
  optional bedtime for the night before and later wake time for the day off.
  Shared Calendar shows them in Month, Week and Day views with owner labels.
  Consented automatic gesture delivery respects the adjusted sleep window
  and skips after-work rituals on a configured day off.
- Language is accessible from the global overflow, not weather settings.

## Needs Attention proposal — awaiting product decision
Classify *action required*, not just high priority:
1. Overdue unfinished work, reminders and dated Activity steps.
2. Actionable items due today/tomorrow.
3. Direct mentions, partner check-in requests, assignee-specific items.
4. Explicit urgent items with no date.
5. High-priority tasks only near a configured preparation threshold.
Collapse multiple references to one Activity, separate informational
Calendar occasions, and respect private visibility, user snooze, completion,
cancellation, archiving and quiet hours. Never automatically infer urgency
from a personal emotional check-in.

## Boundaries
- Check-in alerts are in-app records; OS push/remote delivery in background
  is not yet implemented.
- One personal daily-checkin entry per date remains the existing rule.
  Partner check-in requests are separately stored, each answerable once.
- Check-in request/response history is not exposed outside its participants.
- Days-off exceptions adjust *consented scheduled gestures*. They are not
  yet a universal OS-level quiet-hours controller for all future push.
- New source aggregation and UI require real two-device validation before
  declaring complete. Do not hard-delete shared history.

## Two-phone acceptance tests
1. Verify header layout and overflow menu on narrow Android screens.
2. Toggle Together/Apart and confirm both counters survive on Today.
3. Clear either relationship date, save and reload.
4. Expand/collapse all Today sections: uniform alignment and hints.
5. Post 3 comments to one Activity: one Recent Discussions entry, count 3.
6. Create Calendar event, appointment, To-do deadline, Activity due date and
   dated Activity component within 7 days; confirm correct source labels.
7. Enter a private feeling: recipient sees no entry or notification.
8. Share a feeling: partner receives in-app notification and can read it.
9. Send check-in request: recipient opens it, rates 1–5, adds thoughts and
   discussion topic, replies; sender receives response notification.
10. Change one user’s day off; verify both calendars, as well as per-account
    overrides and skip of after-work ritual on that date.
11. Edit/remove personal gesture template, verify the sender cannot modify
    the other partner's templates, and send each new built-in gesture.
12. Repeat voice message, Calendar/To-do/Notes navigation, Android system
    back and two-back exit, privacy and performance tests.
