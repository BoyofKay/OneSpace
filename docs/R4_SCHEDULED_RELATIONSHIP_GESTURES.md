# OneSpace R4 — Scheduled relationship gestures

Three opt-in schedules: morning (15 minutes after partner wake time), after work (15 minutes after the partner's workday ends, on their selected workdays), and goodnight (20 minutes before the partner's bedtime).

## Privacy and consent
- The sending partner explicitly enables each ritual; each schedule defaults off.
- The receiving partner independently enables "Allow scheduled gestures" in Profile; this defaults off and may be disabled at any time.
- No automated delivery occurs until the recipient has an IANA time zone plus both bedtime and wake-up times. Morning requires wake-up, after-work requires a work-end time and working days.
- The scheduler uses the recipient's *phone time zone*, not their selected weather city. Postgres IANA timezone conversion handles seasonal DST.
- Delivery skips the recipient's sleep interval (including crossing midnight) and only occurs in the 10-minute window following the target. Missed messages are not backfilled.
- One automatic message per sender/moment/recipient-local-day, enforced by a unique index. Each ritual rotates among 10 copy variants; existing manual gesture functionality remains unchanged.
- Automated messages are clearly labeled in gesture history and notifications. In-app alerts only; remote push notifications are not configured.

## Scheduling and verification
- Supabase Cron job: `onespace-consented-gestures`, 5-minute cadence.
- Private non-exposed function: `private.send_due_gestures(timestamptz)`. No execute grant to application users.
- Relevant schema files: 0042–0044. These were saved from the applied remote Supabase migration history.
- Quick sanity query (does not add a schedule): `select private.send_due_gestures(now());` invoked by the privileged DB operator.
- Device QA: both accounts, consent on/off transitions, profile times saved, morning/night and after-work local time, automatic labeling, no duplicate delivery. Test real DST transitions with simulated time only in a controlled test environment; never send surprise messages to production users.

## Not yet supported
Push delivery outside the app, one-off custom schedules, offline sending, holidays or exceptions, and recipient-managed review of individual rituals. These belong to later iterations.
