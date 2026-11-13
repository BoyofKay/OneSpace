# R19 — Feedback-led acceptance checklist, implementation status, and open design work

**Source-only iteration. No R19 APK or release marker update. User test accounts and their records are never reset.**
The shipped R12–R17 APK remains an unchanged baseline. R18 source and the subsequent R19 changes have NOT been built into an installable APK.

## P0 stability and privacy

| User feedback | R19 source response | Status / next gate |
|---|---|---|
| Tagline disappeared | Restored on Today and saved-session sign-in (normal sign-in already uses localized tagline). | Implemented, device QA pending |
| Welcome only first name | FirstName utility for Today; matched cached/fetched profile first name on sign-in and unlock | Implemented, device QA pending |
| Fingerprint stopped | OS authentication now persists across the temporary inactive/background transition; existing FlutterFragmentActivity and USE_BIOMETRIC retained. Device credential/PIN remains supported, Cancel label retained. | Suspected fix, OS device QA needed |
| Getting unexpectedly kicked out | Inactivity gate 5 min → 30 min; background lock 30 seconds → 5 minutes. Does not alter auth token/refresh policy or log out users. | Local lock eased; unexpected server sign-out requires exact logs |
| Experience rating Permission denied | Insert new reviews; update only editable rating/review columns for existing reviews, instead of full-row upsert. | Least-privilege code fix, test with real user credentials |
| Activity likes/dislikes not working | Split insert/update likewise, respecting column grants. | Least-privilege code fix, dual-account test required |
| @ partner in modules | Reusable mention chip, full display-name insertion + notification triggers for shared Calendar events, To-dos, Occasions, Shared Experiences. Notes' existing triggers kept. | Implemented, verify private-content exclusion on both phones |
| Contacts history shows Activity edits | Filter contact audit history by actual visible contact component IDs or standalone contact IDs. | Implemented, QA pending |

## Today / personalization

| User feedback | Source response | Status |
|---|---|---|
| A little love should be a square | Removed wide special card; inserted matching square entry into Today Explore grid. | Implemented |
| Shared Experience square | Added matching square with media icon. | Implemented |
| Regional holiday selection in Settings > Preferences | Removed selection panel from Calendar; added Settings entry. | Implemented |
| Weather temperature unit US/Metric | Local per-device Fahrenheit/Celsius setting, same backend Celsius data, live refresh. | Implemented |
| Birthdays/anniversaries/special dates settings | Settings entry to existing Occasion manager. | Navigation implemented; dedicated date editor still a future UX enhancement |
| Calendar archive through top History | Moved archived toggle to top AppBar history icon. | Implemented |
| Notes archive through top History | Same Notes AppBar pattern. | Implemented |

## To-do and Checklists: actual information model

| User feedback | Source response | Status |
|---|---|---|
| Rename page and + button | To-do and Checklists / Add to-do list | Implemented |
| List with independently checkable items | Existing task row becomes list container, new RLS-protected task_checklist_items and per-cycle task_checklist_checks; list no longer has main checkbox. | Implemented, device QA pending |
| Recurring routine lists | Daily / weekly / monthly / yearly choice, nonrecurring sentinel. Each recurrence cycle has separate completion records and historical checks. | Implemented, midnight/two-phone QA pending |
| Filters to top icon | Visibility, status, due-today in top filter sheet. | Implemented |
| Cancelled red strikethrough | Cancelled parent list uses semantic error color and strikethrough. | Implemented |
| Preserve prior records | No rewriting/deleting existing tasks; recurrence defaults to none. | Verified non-destructive schema migration |

## Notes

- Existing markdown-like note formatting toolbar enhanced with visible, labeled actions for heading/bold/checklist; preview retained. **Not full WYSIWYG**, which requires a richer content model/editor.
- Added RLS-protected note photos table and a private image storage bucket; upload from Android photo picker, signed image previews, soft removal. Save a new note first, then attach photos.
- Notes mention insertion and existing scoped mention notifications retained.
- History entry in top AppBar; existing note versioning/edit concurrency remains.

## A Little Love

- Primary screen regains **Create my own gesture** at the top.
- Removed counts/hints from individual sending tiles.
- Replaced platform-specific emoji for encouragement/missing-together with consistent Material symbols.
- Added **I miss you** gesture category, three baseline messages, and all database validation updates.
- Existing custom templates and sent history preserved.
- Logical grouping/order should be user-tested and further refined.

## Daily Connection

- Removed inappropriate "How is your heart today?" card in favor of two equal action squares: Record my feeling / Check on my partner.
- Underlying requests, replies, feelings journal and permissions preserved.
- **Still open:** redesign request states (pending/answered/expired), records timeline, reaction/response affordances, clearer unread badges and meaningful contextual notifications. Do not pretend this is finished.

## Shared Experiences

- Six category cards: Movie Watchlist, TV Shows, Music Playlist, Books and articles, Games, Others.
- Per-item focus on title and platform; search by title/platform.
- Watch / Play / Open opens the saved URL in its platform, without inventing a streaming link.
- Movies and shows can be marked watched on their card; the transition prompts for a rating. Rating/review available directly from card.
- Removed Planned for and Enjoyed on controls from the editor, preserving existing legacy dates in DB.
- Filters moved into top filter icon, edit history moved to Shared Experiences level, scoped to their own revision rows.
- Archive / Restore via item action menu with an archive confirmation, rather than making archive the primary control.
- **Still open:** richer platform metadata, posters/cover art, playlist/library collection semantics, separate status labels for books/music/games (avoid the term Watched), collection-level analytics and media-provider deep links.

## Data preservation and architecture

Applied additive migrations:
- 0073 recurring nested to-do checklists and completion cycles
- 0074 "I miss you" gesture enum checks
- 0075 protected note images + storage
- 0076 shared content mention triggers + notification object type

RLS enabled on task_checklist_items, task_checklist_checks, note_images, occasion_budget_items. Only shared content triggers cross-module mention notices; private surprise plans do not.

No destructive migration, auth reset, uninstall, data purge, or account switch.

## R19 acceptance steps for the NEXT release — not yet performed on phones

1. Upgrade in place on both existing Android phones; confirm both account sessions, pairing and records.
2. Test saved-session fingerprint and device PIN with phone lock, cancellation, temporary app backgrounding, long idle interval, and failed biometric flow.
3. Create a shared To-do list with five subitems; mark different items from each phone; confirm simultaneous sync and daily/weekly cycle resets. Test cancelled list styling and top filters.
4. Test US vs metric temperature preference per device with original Celsius backend value.
5. Test archived Notes/Calendar behind History and Regional Holidays through Settings; create birthday and anniversary.
6. Test new Note photo upload, signed display, access permissions, and removal on both private/shared notes.
7. Test mention insertion in each shared module, one notification to partner, correct detail navigation; verify no mention notification on a private note/occasion.
8. Rate the same Shared Experience twice from each account; check only own rating updates, no permission error. Like/dislike Activity options, including change of vote.
9. Test six Experience collections, quick Watch/Play/Open, inline watched/rate, archive/restore, and history strictly scoped to Experiences.
10. Verify Contact history contains only Contact revisions, not unrelated Activity edits; inspect review history and UI on both phones.
11. Check all controls under Android 150–200% text scaling in light, dark and seasonal themes.
12. Capture app logs if the app actually signs out (different from a local privacy lock) for more precise auth refresh diagnosis.

## Product-design work not yet delivered

A proper rich-text Notes editor with image blocks interleaved within text, streamlined check-in record lifecycle, an event-driven mention system across individual Comments as well as core documents, more powerful media collections and recommendations, and the full R18 visual polish remain follow-up epics.

Do not conflate a source-only Flutter verification with completed physical Android acceptance testing.
