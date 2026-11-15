# R66 — Forms review part 1: Remember tab and Activities

Require-Firebase-Config: true

Previous signed preview: 0.1.432 (R64+R65).
Preserve the existing com.onespace.onespace.preview Android package,
same signing certificate, Firebase config, biometrics, all account and
partner pairing data, checklists, notes, memories and user documents.
INSTALL AS AN IN-PLACE UPDATE only. Never uninstall or clear data.

## Included since 0.1.432
- One Repeat control for reminders, events and lists.
- Events: location, remind-before, any repeat. Lists: holidays/days off follow Belongs to.
- Notes: pin in strip, photos before first save. Reminders: link any kind of item.
- Activities: Next, Belongs to, countdown on cards, real "Remind us".

## Database
- 0120_r66_sources_events_activities (applied and tested): activities.for_user_id, space_events.location + repeat_rule, reminder sources activity/trip/note, onespace_event_next_on, Today/Remember/Coming up understand repeating events.

## Verification
- "Verify OneSpace iteration" passed on r66-remember-activities.

## Two-phone validation
Follow docs/R66_QA.md.

Controlled R66 signed preview candidate, November 15, 2026.
