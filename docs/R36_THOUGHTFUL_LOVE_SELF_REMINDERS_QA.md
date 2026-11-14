# R36 — A Little Love: personal thoughtful reminders

## Product goal
Help people remember to show love at meaningful moments without
automatically impersonating them or notifying their partner before
the person has chosen the gesture.

## Built
- A Little Love now offers **Remind me to send a little love**.
- The sender selects a gesture category (or any thoughtful gesture),
  morning/after-work/evening suggestion, or a fully custom date/time.
- Suggestions use the *current user's phone local calendar/time*, not
  the partner's timezone. No reminder is created until Save.
- The screen shows when the user last intentionally sent a gesture.
  Only the sender's own sent history contributes.
- The new record uses existing `reminders` and server-side reminder
  delivery; visibility is always **private**, audience always **me**.
- Reminders now display **Open A little love**, opening the gesture
  screen without automatically sending anything. The user still selects
  and manually sends a gesture.
- Existing personalized gesture message pools and random selection
  remain untouched. Existing automatic-ritual settings also remain
  untouched; this is a new opt-in alternative, not a silent migration.

## Security / integrity
- Migration `supabase/schema/0100_r36_personal_love_gesture_reminders.sql`
  adds two nullable intent columns and check constraint to existing
  reminders table. Existing rows remain untouched.
- Database enforces private/me scope, no source object reference,
  and unique active prompts of the same kind at exactly the same instant.
- No new tables, no new FCM credentials, no extra notification channel,
  no ingestion of private mood or private daily check-ins.
- Rollback-only RLS test
  `supabase/tests/0021_r36_personal_love_prompt_rls.sql` passed:
  another partner cannot view the prompt; accidental shared reminder
  is rejected; exact duplicate is rejected; no test rows persisted.

## Two-phone acceptance after verified APK
1. Keep existing two accounts, pairing and FCM registration.
2. On phone A open A little Love, tap Remind me to send a little love.
3. Select a category, the After work suggestion, then a custom future
   date/time. Save without actually sending a gesture.
4. The partner on phone B must see **no gesture** and **no reminder**.
5. At its due time, phone A receives a normal personal reminder.
6. Tap Open A little love; A selects a gesture and sends it manually.
   B then receives the existing gesture push.
7. A's last-sent indicator updates; B's own sender history remains
   independent of A's.
8. Existing one-tap gestures, personalized pools, manual history,
   check-ins, calendars and checklists still work.
9. Test exact duplicate, offline failure, large text and biometric unlock.

## Release gate
Flutter analyze and full test suite, signed APK certificate/package/
Firebase checks, and subsequent real phone validation required.
Source commits are not treated as shipped until the release is published.
