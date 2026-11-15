# OneSpace — Decision Log and Design Rules

This file is the single source of truth for product decisions made with Ahmed (owner) since 15 Nov 2026. Any assistant (Claude, ChatGPT or another) continuing this project must read it first, follow it, and append new decisions here with a date. Do not reopen a "Decided" item without Ahmed asking.

Companion documents in this folder:
- `HANDBOOK_R45.md` — how the app works as built at R45 (features, business rules, automations, open loops).
- `ROADMAP_GAP_REVIEW_R45.md` — the original roadmap checked against the code, and the critique of the R45 requirements document.
- `R46_BASELINE_HYGIENE_QA.md`, `R47_*` — per-iteration notes and two-phone test scripts.
- The live UX spec is a Claude Doc ("OneSpace UX Redesign Specification v1"); its content is summarised in section C below.

## A. Working agreement

| Rule | Detail |
|---|---|
| Repositories | Same GitHub repo (BoyofKay/OneSpace), same Supabase project (OneSpace, ap-northeast-2), Firebase only for push. |
| Approval | Scope is agreed in writing before building. Ahmed approves merges to `main`. |
| Branches | One branch and one Pull Request per iteration (`rNN-short-name`). |
| Database | Every change = a numbered file in `supabase/schema/` AND a recorded Supabase migration. Non-destructive by default; never hard-delete user data. |
| Verification | GitHub workflow "Verify OneSpace iteration" (analyze + tests) must pass on the branch. |
| Release | A signed APK is built only when `release/READY_TO_BUILD.md` changes on `main`. Install as in-place update; never uninstall. |
| Testing | Every iteration ships a plain-language two-phone test script in `docs/`. |

## B. Product decisions (dated)

| # | Date | Decision |
|---|---|---|
| D1 | 15 Nov 2026 | Automatic love rituals (morning/after-work/goodnight auto-sends) are RETIRED. Keep manual gestures and private "remind me to send a little love" self-reminders, to be made smart later. Done in R46. |
| D2 | 15 Nov 2026 | Shared Goals REMOVED from the app (table and data kept). Done in R46. |
| D3 | 15 Nov 2026 | Living arrangement = two facts: **How we live** (Together / Apart; a couple setting changeable anytime from the Today hero, saved instantly with Undo, partner gets a push; on Apart → Together the app offers to save "our journey apart" as a memory; nothing deleted, switching back restores counters) + **Where we are now** (automatic from each phone's time zone and active trips; clocks appear when zones differ; travel is detected). The app must serve ordinary couples, long-distance couples and a travelling partner. |
| D4 | 15 Nov 2026 | Partner is notified when shared items change. Push for meaningful changes (new item, date/time/place change, status change, assignment, @mention, message, removal/restore, gesture, letter, check-in); minor edits only in the Today catch-up feed. |
| D5 | 15 Nov 2026 | Quiet hours: alerts triggered by the partner wait until the recipient's wake-up time; the recipient's own reminders always fire on time; a partner may mark a reminder for you **Urgent**, which overrides sleep. Today is the catch-up place. |
| D6 | 15 Nov 2026 | Push notifications show content (partner name + action + item title/message), in the recipient's app language. Exceptions: Only-me items never reach the partner; nothing about a surprise is pushed to the honoree. |
| D7 | 15 Nov 2026 | Activity chat bubbles show initials only (already true in code). |
| D8 | 15 Nov 2026 | Shared memories: no mutual-delete workflow. Remove (restorable by either partner) + push to the other partner. |
| D9 | 15 Nov 2026 | Period tracking DROPPED. Medication times are covered by repeating reminders. |
| D10 | 15 Nov 2026 | Links between items: a link must save re-typing, carry a lifecycle, or show origin. Keep Activity option→Occasion gift, Activity contact→People, Trip→checklist, Flight→itinerary, Document→itinerary item, Reminder→source (fix: stop alerting when source closes). Simplify generic note linking into "Add a note" inside items. Add "Create from this" actions and one "Linked items" strip per item. |
| D11 | 15 Nov 2026 | Filters: slider (`tune`) icon, never a funnel. Opens a dropdown panel under the icon (not a bottom sheet) with groups of checkbox rows separated by lines, Clear + Apply pinned at the bottom, a dot on the icon and a "Showing: … ✕" line while active. Filters RESET when leaving a screen. |
| D12 | 15 Nov 2026 | History (clock icon) always opens a sub-page with a back arrow: who did what, when. A horizontal row of quick-filter chips: people (Everyone · Me · Partner) then actions (Created · Edited · Completed · Cancelled · Missed · Removed · Restored). Removed rows have a Restore button. |
| D13 | 15 Nov 2026 | Item ⋮ menu: final-status actions first, then Edit, Remove/Restore, Change log (= the history page filtered to that item). |
| D14 | 15 Nov 2026 | Status model: **Completed family** (Completed, Done, Watched, Purchased, Booked, Celebrated, Delivered) · **Cancelled** · **Missed** (system-set, only for recurring cycles that ended unfinished) · **Removed** (= delete; hidden, kept, restorable). One-time items past their date are **Overdue**, never Missed. The word "Archive" disappears from the app; the action is "Remove". Finished/Removed are filters, not part of the change log. |
| D15 | 15 Nov 2026 | Editor sub-page headers always read "Add new [type]" or "Edit [type]"; the item's name is an editable field, never the header. |
| D16 | 15 Nov 2026 | Creation flow: no create popups. "+" opens the item's full page in draft; purpose-based starters for workflow types (e.g. Activity: Buy something · Find a class or service · Plan an event · Decide something · Just a note); draft saves after a title, an empty draft is discarded (no half-empty records); in-place child creation; one contextual Quick add. |
| D17 | 15 Nov 2026 | Share-in: destinations suggested from WHAT is shared (shop link, media link, travel site, maps, unknown site, text with date, photo, PDF, contact) for any app or website. The tray is always the first choice. Tray name: **"Items to sort"** (not "Inbox", which clashes with letters). Placement: a shortcut tile with count, a Needs-attention row when items wait, an entry in the ⋮ menu; no permanent top-bar icon. Private by default. |
| D18 | 15 Nov 2026 | Today: five sections, fixed order: Hero · Since you were away · Needs your attention · Today and the next 7 days · Our space shortcuts. Empty sections show a kind hint ("You're all caught up", "Nothing is waiting on you right now"), never disappear. "A little closer" is a shortcut tile, not a section. Greeting: "Good evening, Ahmed" then "Your space with your [preferred label]". |
| D19 | 15 Nov 2026 | Shortcuts cover ALL features: 3-column grid grouped by tab — Remember: Calendar, To-do & Checklists, Reminders, Notes, Occasions & surprises, People · Coordinate: Activities · Connect: Letters, A little love, Check-ins, Shared experiences, Memories · World: Trips & journeys · Tools: Items to sort, Search our space. Count badge only when action is needed. |
| D20 | 15 Nov 2026 | Push batching for chat messages: at most 1 push per item per 10 minutes ("+3 more"); revisit after real use. |
| D21 | 15 Nov 2026 | Brand line: **"As a couple, we have One Space"** (English in both languages). |
| D22 | 15 Nov 2026 | Innovation Lab Session 01 (Today) verdict accepted: keep Awareness/Connection/Action, Agenda vs Attention split, "good time to talk" windows computed ONLY from stated schedules, local-first cached Today (≤0.5 s from saved copy, ≤2 s fresh), notifications need reason/owner/expiry/action, no half-empty records from quick actions, hideable "on this day" memories. Rejected: hidden push previews, private-by-default, invented approval/vote/confirmation items, incomplete-profile nags, manual Busy status, partner confirmation for arrangement changes, renaming tabs, scores of any kind. Default sharing = Shared, with Only-me exceptions. Each Lab session ends with decisions + backlog with acceptance criteria + won't-do list. |

## C. Won't do (for now)
- No relationship health/compatibility/mood scores, no streaks.
- No manual Busy/Free status; no location or phone-activity tracking.
- No approval/voting workflows; no mutual delete.
- No AI suggestions on Today until the rule-based version has been used for a month.
- No customisable dashboard until the fixed layout is tested by both partners.
- No tab renaming: Today · Remember · Coordinate · Connect · World.

## D. Iteration plan

| Iteration | Theme | Status |
|---|---|---|
| R46 | Baseline hygiene: retire automatic gestures, remove Goals, tagline, stale copy, migration history repair | Done (PR #2) |
| R47 | Reminders for real life: repeat, quiet hours, Urgent, stop when source closes, reminders on Today | In progress |
| R48 | Notifications 2.0: content push, deep links, every chat message and changes notify, batching | Next |
| R49 | Today 2.0: saved copy, one server call, five-section layout, hero model, catch-up, all shortcuts | |
| R50 | Global patterns: filter panel, history page with chips, ⋮ menu, status model, icon dictionary, editor headers | |
| R51 | Creation 2.0: draft pages, purpose starters, Quick add | |
| R52 | Share-in 2.0 and "Items to sort" | |
| R53 | Links: Create from this, Linked items strip | |
| Later | Search coverage (contacts, checklist items, chat), Calendar session, Trips offline documents, smart love reminders, occasion timing rule (salary month), full Arabic, settings consolidation, iOS, AI level 2, voice, account deletion/export | |
