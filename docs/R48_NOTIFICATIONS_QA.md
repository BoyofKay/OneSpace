# R48 Notifications 2.0: what changed and how to test it

Decisions: D5 (quiet hours), D6 (content push in the recipient's language), D20 (chat batching), D21 (brand line).
Spec: UX Redesign Specification v1, sections 5.1–5.4 and backlog B-04, B-05, B-06.

## What changed

| # | Change | Where |
|---|---|---|
| 1 | Every push says who did what and shows the content, for example "Kay sent you a hug" / "Thinking of you at work today". The name is what you call your partner in Profile (partner label) or their first name. The text follows the recipient's app language (English and Arabic phrases). | `0109_r48_notifications_2.sql` (`compose_notification_text`), Edge Function `onespace-push-delivery` v5 |
| 2 | Plain Activity chat messages now notify (before, only @mentions and replies did). Trip messages and experience comments follow the same rule: **at most one push per item per 10 minutes**; messages in between join the next push as "+N more". The notification list keeps one row per item with the latest message. | `notify_activity_comment`, `notify_trip_message`, `experience_comment_notice`, `post_notice` |
| 3 | Meaningful changes by your partner on shared items push: new to-do, new Activity, new memory, a reminder set for you; date/time moved ("Now Mon 16 Nov, 4:00 PM"); status changed (completed, cancelled, decided, bought, booked, celebrated…); a to-do assigned to you; removed or restored (memories included). Wording, notes and tag edits stay silent. Several quick changes to the same item within 2 minutes share one push. Only-me items never notify. | `notice_item_change` trigger on events, to-dos, Activities, occasions, trips, experiences, memories, reminders |
| 4 | Quiet hours: pushes caused by your partner wait while you sleep (Profile → Schedule: bedtime and wake-up, adjusted on days off) and arrive at wake-up as **one** push: "While you were asleep · 4 updates · latest: …". Your own reminders, and reminders your partner marked Urgent, still ring on time (R47 rule). | `queue_notification_push`, `claim_push_outbox` |
| 5 | If you already opened a notification in the app, its push is not sent. | `claim_push_outbox` |
| 6 | Tapping a push opens the exact item: the Activity scrolled to the conversation, the reminder with its Done / Snooze buttons, the gesture pop-up, the event, to-do, trip, occasion, experience or memory. A wake-up summary opens the notification list. A newer push about the same item replaces the older one in the phone's tray. | `push_registration_gate.dart`, `notifications_screen.dart` (`openNotificationTarget`, `openNotificationById`), `activity_detail_screen.dart` |
| 7 | Notification list rows show the same title and text as the push, plus how long ago ("5 min ago", "Yesterday"). The filter icon is the slider icon (D11). | `notifications_screen.dart` |
| 8 | Brand line shortened to **"Two of us, One Space"** and moved under the OneSpace name in the top bar (also on the splash and sign-in screens); removed from the Today page. | `main.dart`, `onespace_strings.dart`, `shared_space_screen.dart` |

Database changes are non-destructive: new columns on `space_notifications` (`action`, `detail`, `push_title`, `push_body`, `push_due_at`, `batch_count`, `memory_id`) and `private.push_outbox` (`quiet_deferred`, `fold_count`), widened kind checks, replaced functions, new triggers. Existing notifications were given push text without sending anything.

Known limits (planned for later iterations):
- Opening an item your partner has since removed shows the screen's normal view; the "This was removed by Kandice · Restore" banner comes with the status model in R50.
- Arabic push phrases are written in the masculine form; full Arabic review is on the later list.
- "Since you were away" on Today (R49) will show the silent minor edits.

## Test script (two phones, both on this build)

Call the two phones **A** (Ahmed) and **K** (Kandice). Make sure both allowed notifications when the app asked.

1. **Top bar:** on any main tab, the top bar reads "OneSpace" with "Two of us, One Space" underneath. The Today page no longer shows the line in its body.
2. **Gesture push:** on A, send K a hug with a message. K's phone shows "Ahmed sent you a hug" with the message. Tap it: the gesture pop-up opens.
3. **Chat message:** on A, open a shared Activity and write a plain message (no @). Within about a minute K gets "Ahmed · <Activity title>" with the message text. Tap it: the Activity opens scrolled to the conversation.
4. **Batching:** right after step 3, A sends three more messages. K gets **no** new push straight away. About 10 minutes after the first push, K gets one push showing the latest message and "(+2 more)". The tray shows one entry for that Activity, not four.
5. **Read before push:** A sends another message; K opens the notification list in the app before the next push is due. No push arrives for it.
6. **Moved event:** A moves a shared event to another time. K gets "Ahmed moved <event>" / "Now <new day and time>" in K's own time zone. Tap: the event opens.
7. **Minor edit:** A changes only the event's title or notes. No push.
8. **To-do assigned:** A creates a shared to-do assigned to K. K gets "Ahmed assigned you <to-do>". Then A marks it done: K gets "Ahmed completed <to-do>".
9. **Memory removed and restored:** A removes a shared memory: K gets "Ahmed removed <memory>"; A restores it: K gets "Ahmed restored <memory>".
10. **Reminder for you:** K sets a shared reminder for A. A gets "Kay added a reminder for you" / "<title> · <time>". At the due time A gets "Reminder from Kay"; tap opens the reminder with Done / Snooze.
11. **Quiet hours:** on K, set Profile → Schedule bedtime to a time 5 minutes ago and wake-up 15 minutes from now. A sends K a hug and moves an event. K's phone stays silent. At the wake-up time K gets one push "While you were asleep" / "2 updates · latest: …"; tapping opens the notification list. Clear or restore K's real schedule afterwards.
12. **Only-me stays private:** A creates an Only-me to-do. K gets nothing.

Verified on the live database before release (inside transactions that were rolled back, so no data changed): chat batching and "+1 more", activity decided, to-do completed, silent title edit, quiet-hours hold to wake-up, wake-up summary folding 4 updates into one, read-before-push skip, gesture wording, moved-event wording in the recipient's time zone, memory added/removed, reminder for partner, private to-do silent.
