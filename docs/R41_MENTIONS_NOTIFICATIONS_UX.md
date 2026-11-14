# R41 — Authorized reminders mentions and notifications UX

## Delivered
- Shared Reminder text details now offers a real @partner insertion
  control, using the authenticated partner display name.
- Additive SQL migration 0104 installed the actual server notification
  trigger. A mention only notifies when the reminder is shared, active
  and the text contains the other partner's full @display_name.
- Does not notify when the reminder is private; does not expose private
  reminder details to the other account.
- Server-owned (recipient,kind,object_id) conflict key deduplicates
  mention alerts; editing unrelated data does not create new mentions.
- Notification deep link opens the precise Reminder record, and task
  notifications open the precise checklist, not just its module.
- Notification list filter moved to top-right. Mark-all-read remains
  accessible and does not erase notification history.
- General R40 record action history remains independent from recipient
  reminder outcome history and mention alerts.

## Security evidence
- R41 two-partner rollback-only SQL test 0025 PASS: authenticated
  sender created shared mention, other partner account could read
  the mention alert, private reminder emitted no mention, private
  reminder remained invisible, and unrelated edit did not duplicate
  mention. All test data rolled back.
- Source RLS and user preferences (quiet hours, pairing, push tokens)
  are unchanged by the notification trigger.
- No token, password, document body or private note text is copied
  into the notification headline.

## Remaining mention roadmap
- Goal and Memory free-text fields still need corresponding object
  kinds, secure notifications and exact-object routing. Do NOT present
  text insertion as full mention functionality before server tests.
- Other components' rich content, comments and attachments require
  their own lifecycle and revocation logic. No mention controls on
  dates, currency, selects, status fields or private text.
- Full automated Flutter verification and signed preview required;
  R40 Release 415 was pinned earlier and does not include this batch.

## Phone QA
1. On phone A create a shared Reminder and @mention partner in details.
2. On phone B verify mention alert opens exact reminder and normal
   reminder schedule/recipient status remains independent.
3. Create a private reminder containing identical text; phone B must
   receive no mention and see no private reminder.
4. Change a shared reminder without changing mention text: no duplicate.
5. Verify Notifications top filter All/Unread, Mark all read,
   checklist deep-link and R34 expanded checklist remain functional.
6. Verify the R40 dark/light season contrast and audit history UI.
