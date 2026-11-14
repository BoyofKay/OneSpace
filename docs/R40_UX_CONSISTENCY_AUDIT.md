# R40 — OneSpace UX consistency audit and staged implementation
Date: 2026-11-14. A source-level first pass, **not** a claim that every
screen and field has been fully standardized or phone-tested.

## Universal product contract
1. **Collection screens:** AppBar top-right has History (archived and
   recoverable items) when records can be archived, and Filters when
   state, owner, privacy, category or other filters apply. Search should
   be accessible near the top of a list, with clear reset state.
   Historical logs are distinct from archived content.
2. **Record actions:** Provide Edit, Archive/Remove, Cancel, Reopen,
   Restore or Detach only where meaningful and authorized. No hard
   delete for records where referential integrity, historic receipts or
   partner outcomes require preservation. Destructive actions require
   context and confirmation. View-only recipients do not get edit actions.
3. **Who/what/when:** Server-authenticated actor, fields affected and
   timestamp. No password, health details, private text or media copies
   in general audit log; preserve existing feature-specific revisions.
   History is append-only and follows the **original object RLS**.
4. **Mentions:** `@partner` for authorized, editable *shared free-text*
   fields and rich text. Date, currency, rating, visibility, location,
   checkboxes, secret/private or disabled fields should not offer a
   mention control. Server must own authorization, notification and
   deduplication; text insertion alone is **not** working notification.
5. **Search:** Global discovery plus local content/metadata search for
   every data-bearing module; RLS mandatory. Not every multimedia
   attachment should have its OCR/transcription indexed automatically.
6. **Contrast:** At least WCAG 4.5:1 ordinary text and 3:1 large text
   and UI icons, in four palettes, system/light/dark, and seasonal themes.
   Visual overrides including translucent image overlays need separate
   on-device checks for actual composited backgrounds.

## Implementation delivered this batch
- Reusable `RecordListTopActions` with top-right History and Filters.
- Goals: top-right archived History + status Filters, title/description search.
- Memories: top-right archived History + visibility Filters;
  existing people/place/photo-tag search retained.
- Notes: top-right archived History + visibility Filters;
  existing rich-text content search retained.
- Reminders: top-right archived History + completed Filters,
  title/details search, existing recipient outcome history retained.
- Global Search: index Goals and Memories in addition to previous
  categories; top-right result-type filter and direct goal/memory/task
  record deep links. Search still does not cover every nested record.
- Theme: contrast test iterates 4 palettes × 2 brightness modes × all
  seasonal treatments for core text surfaces and semantic containers.
- Additive migration 0103: server-only actor/field/time history for
  notes, tasks, goals, memories, calendar events, reminders, occasions,
  shared experiences. Does not backfill old edits. RLS test 0024 PASSED,
  including private partner isolation, archival and restoration.
- Shared history view linked from 8 record UI surfaces.
- Rich-text Quill Notes now offer @partner insertion in editable shared
  documents; existing note mention trigger handles actual alert delivery.

## Source-level audit findings / remaining gaps
| Module | Existing coverage | Remaining work |
|---|---|---|
| Today / Dashboard | Aggregated relationship indicators | Audit every CTA, theme overlay and accessible contrast |
| Coordinate / Activities | Activity filters, text search, history & per-component changes | Normalize top placement and component-level action permissions |
| To-do / Checklists | Top filters, status history, editable lists, R34 crash fix, R37 speech | Per-subtask action/mention rules, private checkmark audit |
| Notes | Rich Delta, images, R38/R39 linked records; now top toolbar | Rich mentions phone QA, attachment/field-level audit |
| Goals | CRUD-style editor, archive/restore; now top toolbar and search | Confirm cancel/status semantics and progress history |
| Memories / Scrapbooks | Search across text/photo metadata, archive/restore; now top toolbar | Photo and layout-level changes, image text contrast |
| Calendar | History at top, events, mentions, source notes | Standardize filters, recurring edit and timezone validation |
| Reminders | Per-recipient outcome history; now top toolbar and text search | Source-level archive notifications and fine-grained history |
| Contacts | Top history + search + restore | Align filters with common toolbar, validate each card action |
| Occasions | Private/shared planning, shopping/budget/revisions | Full module-level search, per-step actions/history consistency |
| Shared Experiences | Suggestions, interest, comments, reviews, revisions | Full comment/review search and deletion/restore model |
| Trips / Documents | Items, documents, trip preparation | Search all attachment metadata, offline availability, restore flows |
| Check-ins / Letters / Chat | Dedicated interaction workflows | Mentions and message editing may have intentionally different lifecycle rules |
| Notifications | Read/unread controls | Top filter consistency, immutable notification event history |
| Settings / Profile / Auth | Settings and account controls | Controls are not general CRUD records; audit security changes separately |
| Global Search | RLS title search across 14 categories | Nested object search, body/metadata indexing, archived opt-in |

## Safety, action-policy nuances
- Users may **archive / restore** sync records. Hard deletion is not
  automatic because connected reminders, child records or audit history
  might become orphaned. The record remains accessible according to RLS.
- A private note shared read-only is still not editable by its recipient.
- A shared object must never link or reveal a private surprise.
- Never generate notifications from mere rendering/search/edit preview.
- No automatic @mention triggered for private content.
- A physical-device crash fix is not established by source tests alone.

## Next iteration priorities
1. Green Flutter/analyzer/test and signed Android preview for current R40.
2. Expand top History/Filters to all remaining collection screens.
3. Complete per-component CRUD/restore permission matrix, including
   dependent objects, comments and attachments.
4. Add authorized mentions and notification routing for remaining
   *supported free-text* fields, with backend integration tests.
5. Search nested metadata/child items and authorized archived records.
6. On-device contrast and font scaling testing for image-based layouts,
   empty states, dark mode and season overlays.

## Acceptance
- Both existing phone accounts upgraded in place without data reset.
- History and Filters always accessible at screen top for applicable
  collections; audit logs record authenticated who/what/when.
- Search respects private/shared RLS.
- Shared Quill @mention notifies only intended partner; private note
  cannot notify.
- Confirm checkout of R34 checklist expansion, R37 speech, R35–R36
  reminders, R38 Notes and R39 backlinks, and FCM gestures.

## Palette contrast clean-up
- Removed hard-coded `Colors.red` error text from Goals, Memories and Notes in favor of `Theme.of(context).colorScheme.error`.
- Automated 4-palette × 2-mode × seasonal scheme regression remains required; physical composited-image contrast remains separate QA.

## Subsequent R41–R42 source work (separate from signed R40)
- R41: shared Reminders now have a real @partner insertion and server notification trigger 0104; SQL 0025 recipient-side RLS test PASSED. Notifications All/Unread moved to top-right, and task notifications navigate to the exact checklist.
- R42: Global Search additionally queries text content in Activities, Calendar details, Notes body, Goals description, Memories body, Reminders details and Shared Experience description. Results are deduplicated by type and record ID, queried only through source table RLS, without copying private data into a search index. This still does not include every nested component or archived record.
- Both require Flutter analyzer, tests, signed APK and two-device acceptance before feature completion claims.
