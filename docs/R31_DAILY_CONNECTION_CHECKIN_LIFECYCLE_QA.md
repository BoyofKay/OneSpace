# R31 — Daily Connection: calm request lifecycle and two-phone QA

## Built
- New partner check-in requests remain open for seven days by default, then
  show **Expired** rather than remaining an indefinite pending obligation.
- Existing old requests keep `expires_at = NULL`, preserving their original
  answerability. No historical record is purged or rewritten.
- The server-owned expiration default cannot be forged from the Android
  client; the existing recipient-only RLS and column grants remain unchanged.
- A server trigger rejects replies to expired requests and still requires
  a rating and only one reply.
- The request timeline distinguishes **To answer**, **Sent**, and **History**,
  with counts, status icons, remaining time, collapsible details and contextual
  reply actions. Answered/expired history remains viewable.
- On-screen expiry labels refresh while the page stays open without polling
  the server or scheduling additional push delivery.
- Expired deep links do not automatically open a reply editor.
- Existing personal Daily Check-in journal, private-sharing controls,
  reply notifications, and Firebase push configuration are unchanged.
- Today → Needs Attention excludes expired, unanswered requests at the
  SQL aggregation layer, even though those same records remain in
  Daily Connection history and original notification history.
- No auto nagging, default resending, or emotionally urgent inference.

## Database and regression
- Additive migration `supabase/schema/0096_r31_gentle_checkin_expiry.sql`
  deployed to the existing OneSpace Supabase project.
- `supabase/schema/0097_r31_exclude_expired_checkin_attention.sql`
  updates the existing Today attention aggregator without changing its
  privacy model or unrelated activity/task rules.
- Rollback-only test `supabase/tests/0017_r31_checkin_expiry.sql` passed:
  new request seven-day deadline; server rejects a late reply;
  valid reply is accepted with a server timestamp; legacy no-deadline
  request remains answerable; expired request is absent from Today →
  Needs Attention; no test records persist.
- Pure Dart rules and Flutter unit tests for status boundaries,
  personalized filters, legacy compatibility, timeline ordering, and hints.

## Verify on two Android phones
1. Upgrade over the current preview using the same signed APK identity;
   keep both original accounts and pairing.
2. Phone A sends a gentle request; phone B receives its existing FCM
   notification and sees it in **To answer** automatically.
3. Phone A sees the request in **Sent**, with the deadline label.
4. B responds; A receives the existing response notification. Both
   see **Answered** and the same conversation details in **History**.
5. Try opening an already answered request from Notifications: it must
   not open a second reply editor.
6. Ensure old requests without a deadline are still answerable.
7. An expired test request must show **Expired**, disable Reply, remain
   visible in History, and reject a forged API response.
8. Confirm neither partner receives automatic resend/escalation spam.
9. Daily feeling journal: create private and shared entries; private
   entries remain protected, shared entries notify the partner normally.
10. Check biometric/PIN unlock, long idle/backgrounding, two phone
    time zones, large fonts, and Arabic layout.
11. Confirm Reminders, To-do/Checklists, Shared Experiences, Trips,
    Scrapbooks, and two-way Firebase love gestures remain intact.

## Gates
- Verify current committed Flutter dependencies, analyze and full test suite.
- Then trigger exactly one signed preview build after verification succeeds.
- Do not call it tested on phones before real acceptance.
