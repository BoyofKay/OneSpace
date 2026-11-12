# OneSpace – Calendar, Memories and Speed Acceptance

## Release scope (developed, not yet user-accepted)

### Performance and instrumentation
- One `get_home_snapshot()` request replaces multiple space/member/summary calls.
- A two-minute user-scoped memory cache avoids duplicate membership queries for tabs.
- Tasks stream starts before optional member-name lookups finish.
- Home does not re-request data on every quick tab switch. Pull down to refresh.
- App performance (Profile icon → App performance) displays timing numbers only.
- Database remains in **Seoul (`ap-northeast-2`)**. A round trip from Saudi Arabia
  can be slow; do not relocate the live project during this beta without a
  dedicated migration and rollback plan.

### Calendar
- Date-only events and annual occasions; includes task target dates.
- Future countdowns; annual dates recur, including Feb 29 only on leap years.
- Create, edit, archive/restore; private/shared RLS.
- Private owners can grant and revoke read-only access.
- Not delivered: timed meetings, time zone selection, scheduled push notifications.

### Memories
- Dated text journal; create/edit, pin, archive/restore.
- Shared/private, revocable read-only grant.
- Conflict detection for stale edits.
- Not delivered: secure photo/video attachments, rich text, geotags.

## Acceptance steps: Samsung and older phone

- [ ] Install the published APK over the existing `.preview` version; do not clear data.
- [ ] Cold-launch OneSpace. Use the OS Back gesture to leave a phone-auth prompt.
- [ ] Open Home, Tasks, Calendar, Lists and Notes; none should show a permanent spinner.
- [ ] Open top-right Profile → App performance. Copy the measured timings.
- [ ] Switch Home → Tasks → Home 5 times. No new Home HTTP request should
      be launched on every switch.
- [ ] Test over Wi-Fi and cellular and on the older Android device. Record
      cold-launch time, Home time, and Tasks time separately.
- [ ] Account A creates a shared calendar event, an annual occasion, and a
      private occasion. Account B sees only the shared entries.
- [ ] Account A shares the private occasion view-only. B can read but not edit.
      A revokes; B refreshes Calendar and can no longer fetch it.
- [ ] Test Feb 29 yearly anniversary and that the same day remains correct
      when both phones have different time zones.
- [ ] A creates a shared memory with an old date and a private memory.
      B reads the shared one, but not the private one.
- [ ] A grants the private memory view-only. B cannot modify the record;
      after revocation it disappears on a fresh query.
- [ ] Verify that existing tasks, lists, notes and pairing remain intact.
- [ ] Note any Arabic RTL clipping or untranslated strings.

## Diagnostic data handling

The in-app timing report stays only in device process memory and is not
sent automatically. It does not collect email addresses, access tokens,
user-generated journal entries or identifiable content.

## Server-side regression

- `supabase/tests/0007_calendar_home_rls.sql`: home response + private
  calendar sharing and revocation for paired accounts.
- `supabase/tests/0008_memories_rls.sql`: private Memory isolation,
  owner-controlled sharing and authorized Home totals.
- `test/calendar_rules_test.dart`: yearly recurrence, leap dates and
  timezone-neutral day countdowns.

Release-mode build success means **compiled**, not a verified performance
improvement. Verify actual timing before claiming the app is faster.
