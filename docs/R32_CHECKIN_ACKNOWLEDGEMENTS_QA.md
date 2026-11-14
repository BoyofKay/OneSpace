# R32 — Optional Check-in Acknowledgements

## Product intent
After receiving a response to a gentle check-in, the original sender may
acknowledge it with one quiet supportive choice: Sending love, Thank you for
sharing, or Sending a hug. This does not imply a new request, automatic
follow-up, partner obligation, or push notification. Both participants see
the current choice, but only the original sender can create/change it.

## Implementation
- Additive table `public.partner_checkin_acknowledgements`, with one row
  per answered request. No rows from R31 are rewritten or deleted.
- SQL migration: `supabase/schema/0098_r32_checkin_acknowledgements.sql`.
- RLS restricts SELECT to both current participants of an *answered* request,
  INSERT/UPDATE to the original request sender, with no UPDATE permission
  for user_id or request_id.
- The database serves choices through one realtime stream on the Daily
  Connection page, instead of a subscription for every history card.
- Senders can select/update their own acknowledgment without touching the
  response or other partner's data. Recipients see the saved acknowledgment
  automatically.
- No notification type, Firebase worker configuration, existing gesture
  scheduler, account settings or Android permissions are modified.

## Verification
- Rollback-only RLS regression:
  `supabase/tests/0018_r32_checkin_ack_rls.sql` PASS. Assert:
  no acknowledgment before reply; sender-only insert and change; respondent
  can view but not edit; all QA data rolled back.
- Security introspection confirms RLS true, three policies, no authenticated
  user_id UPDATE permission, and Supabase realtime publication enabled.
- Flutter automated tests for exact request matching, labels and sender-only
  eligibility. Analyzer and full Flutter tests required before any APK.

## Two-phone acceptance (future signed preview)
1. A sends a check-in; B replies.
2. A sees the reply and optional acknowledgment choices.
3. A chooses Sending love; B sees the same acknowledgment without
   refreshing manually; existing push stays unchanged.
4. B cannot change A's acknowledgment. A switches to Thank you for sharing,
   and B sees the updated choice without duplicate data.
5. Neither person can react before a request is answered.
6. Acknowledge a previously answered legacy request without a deadline.
7. Verify no accidental new check-in, duplicate response or surprise push.
8. Confirm R31 pending/answered/expired categories remain consistent on both
   phones and Today omits expired requests.
9. Verify private feelings, shared records, pairing, biometrics, Notes,
   To-do/Checklists, Trips, and Shared Experiences remain unchanged.

## Release policy
This is **source-only** until analyzer/tests and the next controlled signed
APK succeed. It is NOT included in the separately triggered Release 408.
