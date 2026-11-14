# R44 — Expanded who / what / when audit history

## Purpose
Continue R40 action-audit standard for additional relationship data:
- Trips & journeys (`shared_trips`)
- Standalone saved contacts (`saved_contacts`)
- Personal daily check-ins (`daily_checkins`)
- Partner check-in requests/responses (`partner_checkin_requests`)

## Backend
- Additive migration 0105 extends the existing
  `record_action_history` kinds and its **source-object RLS**.
- Private trips, contacts and check-in histories are visible only to
  accounts already authorized to read their source record.
- A new trigger function writes server-observed actor `auth.uid()`,
  event time, action and names of changed fields. It does not copy
  names, email, phone numbers, emotions, message text, credentials,
  media, or travel-document contents into the general audit log.
- For trips, status cancellation/reopening and archive/restore are
  differentiated. Saved contact archive and restore are recorded.
- Other changes are labeled edited; creation is labeled created.
- Existing individual feature revision histories remain available.
  No retroactive reconstruction of old history is attempted.
- Historical events are immutable through app Data API grants.
- No new client write privileges, and no existing user data deleted.

## Verification
- SQL rollback-only test 0026 PASSED after migration 0105:
  test fixtures as migration owner because direct table insert is
  restricted (normal app writes may use RPC).
  **History reads** are tested under authenticated partner A/B RLS.
- Four new event types generated, trip cancellation recorded,
  contact archive/restore recorded, private gratitude edit logged as
  the *field name* only, and partner B could see shared trip actions
  but not private contact/check-in actions.
- No test fixtures persisted.
- New action history UI uses the existing RecordActionHistoryButton/
  View, which fetches through table RLS.
- Flutter analyzer and full tests required before signed Android APK.

## UI entry points
- Trip detail app bar: server Record action history; existing trip
  revision history remains distinct.
- Expanded saved contact: both prior Contact edit history and new
  server Record action history for direct saved contacts only.
- Partner check-in request expansion: server action history.
- Daily Check-in expansion: server action history.

## Important boundaries / next gaps
- Child records such as trip documents, experience reviews,
  calendar subcomponents, and per-user checklist checkmarks need
  separate sensitive-data retention policies before standardized
  history can be added.
- Entries with no server-created events before this migration do not
  have historical backfill.
- Some records use dedicated revision logs that show detailed
  before/after fields; the generic audit is metadata-only.
- If source access is revoked, the history becomes unreadable by
  that account even if the event once existed.

## Two-phone acceptance
1. Update in-place with no data loss.
2. Edit shared Trip; both accounts see actor and changed fields.
3. Archive/restore saved private contact; only its owner sees events.
4. Create/edit a private daily check-in; the other phone must never
   show its event history, notes or notification.
5. Send a partner check-in request and respond; both entitled users
   may see request-history metadata, with original lifecycle intact.
6. Reconfirm shared/private Notes, reminders/mentions, checklist
   expansions, speech, calendar, occasions and push notifications.
