# R43 — Collection-screen History, Filters and searchable content

## Scope built
- **Trips & journeys:** standardized top-right History/Filters using
  RecordListTopActions; archived-only history remains recoverable;
  Upcoming/Past/All filters moved into the top sheet; local search now
  checks title, destination, origin and trip notes.
- **Occasions & surprises:** top-right History/Filters; Upcoming,
  Only me, Both of us and All filters; on-screen search checks title,
  honoree, notes and occasion kind, all already RLS-filtered.
- **People & Contacts:** top-right Recently Deleted History and
  All/Saved directly/From Activities filters; existing contact-edit
  history is kept as a separate top-right action. Search of contact
  card fields is unchanged. Restore does not delete activity data.
- **Shared Experiences:** top-right archived History and centralized
  Status/Category/Mutual filters. Existing revision history remains
  separate and accessible. Search now also includes description.
  Discovery category tiles are retained as deliberate shortcuts.
- **Coordinate (embedded tab):** History and Filters sit in its own
  top header (no nested app bar). Archived rows are shown only through
  History, not mixed into the All active filter; existing activity
  title/body search and separate Activity revision history remain.
- **Daily Check-ins:** top-right conversation History, conversation
  status and journal visibility Filters. Two independent searchable
  surfaces cover authorized check-in messages/gratitude and partner
  conversation messages/topics, without merging private content.

## UX contract
- Archived/deleted records and **edit/action history** are not the
  same thing. Both are available where applicable.
- History refers to recoverable, archived records. Filter sheets
  adjust status/visibility/category. Search stays at the top of the
  screen and must work when a filter or History view is selected.
- View-only and private content protections remain on the existing
  backend and database policies; presentation controls never confer
  rights. No new Supabase grants and no user data migrations in R43.
- Restore and edit actions remain the original ones, rather than
  introducing unsafe hard-delete shortcuts.
- Avoid extra backend queries when toggling local collection filters
  or searching loaded rows. Fetch is still limited by each screen's
  original RLS and pagination; global search provides wider coverage.

## Tests and release gate
- Run all committed Flutter dependencies, analyzer and tests,
  especially legacy/new checklist expansion, native voice, note links,
  reminder mentions, top-bar widget tests and theme contrast.
- No change to package name, pairing, token registration, Firebase
  configuration, privacy or signing keys.
- Signed Android APK must independently repeat the gate, compile
  Kotlin and be installed in place on both phones.
- The previous R42 Release 416 is a separately pinned version and
  does not contain R43. Never claim new features are in 416.

## Acceptance on two Android phones
1. Open Trips/Occasions/Contacts/Experiences/Coordinate/Check-ins.
   History and Filters appear in each screen's top action area.
2. Switch History on/off and confirm archived content isn't mixed
   into normal lists. Restore an authorized archived item.
3. Check filter combinations and search within title, notes, names,
   destinations, experience descriptions, gratitude and conversation
   messages; confirm no cross-partner private result.
4. Confirm existing revision/event history remains independent of
   archived records and shows who/what/when where supported.
5. Recheck R34 legacy/new checklist expansion without crashes,
   R37 voice reading, note references, occasion prep and FCM.
6. Manually inspect font/background contrast across palette/mode/
   holiday combinations, dynamic text scaling and image overlays.

## Remaining work
- Other screens: Goals/Memories/Notes/Reminders have R40 controls,
  but individual editors, nested components, comments, photo galleries
  and attachments still need a field-level CRUD/restore audit.
- Authorized @mentions and action-history coverage are still not
  universal; checkin confidentiality takes precedence over mentions.
- Full nested/attachment search and safely searchable archived
  content are future R44+ work. Global Search still uses capped
  original table queries, not a universal full-text index.
