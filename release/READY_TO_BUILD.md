# R42 — Shared Reminder Mentions and Searchable Content

Require-Firebase-Config: true

Previous published signed preview: 0.1.415.
Build the next Android preview over the same package,
com.onespace.onespace.preview. Preserve the existing Android signing
certificate, Firebase configuration, paired accounts, checklist records,
all private and shared data. Do not clear user data or reinstall fresh.

## Included R41 and R42
- Shared reminders can @mention the partner from their details field.
  The backend validates shared visibility, sender membership and the
  partner display name. A private reminder never sends a mention.
- Notification All/Unread filters moved to the top action bar.
- Tapping a task mention or notification opens that exact checklist.
- Global search now searches text in Activities, Calendar events,
  Experiences, Notes, Goals, Memories and Reminders in addition to
  existing title-only categories. Results are deduplicated.
- A selected category avoids unrelated queries for performance.
- All source searches remain protected by original table RLS and
  individual request limits. No mirrored private search index.
- Includes earlier R34 stable legacy/new checklist expansion, R35–36
  reminders, R37 voice readout, R38–39 notes cross-links and R40 UX
  consistency, audit who/what/when, and theme contrast safeguards.

## Backend and source verification
- Additive Supabase migration 0104 deployed, no user rows wiped.
- Rollback-only two-account test 0025 PASS: authorized shared mention
  creates one recipient notification; private one stays hidden;
  unrelated edit does not create a second mention.
- Full Flutter source verification run 57 SUCCESS on source commit
  7fb2ea009aa002a3287409e33a0501242f7f8f73.
- Signed Android pipeline must independently rerun analyzer and full
  tests and compile Kotlin, validate package/certificate/Firebase,
  and publish one verifiable preview APK.
- Do not claim device acceptance before testing on both phones.

## Two-phone acceptance
1. Install APK in place over 415, no uninstall/reset.
2. Phone A creates shared reminder with @partner; B receives alert,
   which opens exact reminder; private reminder stays private.
3. B opens task notification and lands in correct checklist.
4. Search an activity body, event details, note body, and reminder
   details; category filtering returns only that section.
5. Reconfirm working old and new checklists, R37 voice, gestures and FCM.
6. Check top History/Filters and audited changes from 415.

Controlled R42 signed Android preview, November 14, 2026.
