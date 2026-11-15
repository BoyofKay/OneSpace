> Generated 15 Nov 2026 by Claude from code ae0870b (R45). PDF version shared with Ahmed. Later decisions: see DECISION_LOG.md.

# 1. Summary

This document does three things:

- **Part A** turns **RoadMap.docx** (the original vision, all later feedback and clarifications) into bullet-point requirements. It keeps the *latest* instruction where you changed your mind, and classifies each one against the **actual code and live database** (commit `ae0870b`, R45).
- **Part B** reviews **OneSpace_Roadmap_Reviewed_Requirements_R45.docx** (ChatGPT's own self-assessment of the same roadmap).
- **Part C** sets out how I propose we continue working together.

> **Headline.** My independent count is lower than ChatGPT's. The R45 document marks 108 of 179 items "Fully implemented" (60%). Using a stricter test ("does it do what Ahmed actually asked, end to end?"), about **53%** of the product requirements are fully met. The difference is mainly items where *code exists* but the specific behaviour you asked for is missing (timing rules, notifications, search coverage, labels). The R45 document also misses several of your original pain points entirely.

**Status key:** [FULL] does what was asked · [PARTIAL] part of it · [DIFF] built, but not the way you asked · [NOT] not built.


# Part A: RoadMap.docx organised and checked against the code

## A1. The original problems OneSpace must solve

| ID | Problem you described | Status | What the code does today |
|---|---|---|---|
| P-1 | Two separate lives; I forget details of her life | [PARTIAL] | Notes, contacts, occasions and memories exist. Contacts are not in global search, and private "partner preferences" have no dedicated structure (only free notes). |
| P-2 | Different time zones make appointments hard | [PARTIAL] | Clocks per partner; events with zones; reminders delivered at the right instant. No pre-event alerts, no "her local time" shown when you create an alert for her. |
| P-3 | Requests made while I sleep/work get dropped | [PARTIAL] | Activities and Reminders capture requests, but a plain chat message in an Activity does **not** notify, and reminders cannot repeat. |
| P-4 | Phone alarms to wake her or be free for her call broke at a time change | [PARTIAL] | Reminders are absolute instants (DST-safe). There is no recurring "call/wake" alarm that follows *her* time zone, and no quiet-hour awareness. |
| P-5 | Remember her friends' and neighbours' names | [PARTIAL] | People & contacts with notes, import from phone. **Not globally searchable**, and no "relationship to Kandice" field (notes only). |
| P-6 | She asks for research (heater, pillows), forgets to review, then gets upset | [FULL] | Coordinate Activities with options, comparison, likes, decisions and outcomes cover this workflow well. The silent-chat gap (P-3) is the remaining weak point. |

## A2. Shared schedules, routines and everyday tasks

| ID | Requirement (latest intent) | Status | Evidence / gap |
|---|---|---|---|
| R-1 | Coordinate schedules, appointments, wake-up times and calls across time zones | [PARTIAL] | Clocks, zoned events, reminders. No wake-up/call planner and no partner-local-time preview. |
| R-2 | Save important notes, links, hiding places, reminders | [FULL] | Notes 2.0 (rich text, images, links), Reminders. |
| R-3 | Track last menstrual cycle | [NOT] | No cycle tracking anywhere (not mentioned in the R45 document either). |
| R-4 | Medication times, pick-ups, gas, car wash, laundry | [PARTIAL] | One-off Reminders or recurring checklists only. **Reminders cannot repeat.** |
| R-5 | Shared to-do lists and reusable checklists (car items, before going out) | [FULL] | Checklists with sub-items, per-person ticks, recurrence. |
| R-6 | Automated reminders, morning check-ins, safety alarm | [PARTIAL] | Server reminders (one-off); check-ins are manual; **no safety alarm**. |
| R-7 | Task priority without a due date unless one applies | [FULL] | Priority with optional target date. |
| R-8 | To-do title "To-do and Checklists" | [FULL] | Screen title matches. |
| R-9 | Button "+ Add to-do list" | [DIFF] | Button reads "Create checklist". |
| R-10 | Lists with items inside that can be ticked | [FULL] | Sub-items with ticks. |
| R-11 | Remove the parent checkbox (concept changed to sub-items) | [FULL] | Parent completes via status; items are ticked. |
| R-12 | Filters (visibility, status) moved to a filter icon at top | [FULL] | Filter icon in To-do header. |
| R-13 | Cancelled = red strikethrough; completed = strikethrough, not red | [FULL] | Styling implemented (verify colours on all palettes). |
| R-14 | Switch between all to-dos and "what to do today" | [FULL] | "Due today / overdue" filter. |
| R-15 | Recurring checklist opens fresh each cycle, closes the previous one, keeps history | [FULL] | Per-cycle, per-user completion rows; history retained. |
| R-16 | Who uses it (A, B, both), shared or private, separate completion for each person | [FULL] | Assignee + visibility + per-user ticks. |
| R-17 | Recurrence: weekdays, weekends, every N, month days, working days | [FULL] | All supported in `checklist_schedule.dart`. |
| R-18 | Recurrence time zone (household zone or responsible person's zone) | [PARTIAL] | Supported, but the override is a **typed IANA string**. |
| R-19 | Days off / holidays as exceptions defined on the checklist | [PARTIAL] | Days off yes; holidays **US federal only**, ignoring your selected holiday countries. |
| R-20 | Legacy tasks moved into one "Old checklist" (no legacy compatibility mode) | [FULL] | Legacy tasks migrated as sub-items. |
| R-21 | Old Lists & Checklists module removed from UI and database | [FULL] | Retired (migration 0079). |
| R-22 | No dedicated shopping module; the new concept covers shopping | [FULL] | Shopping via checklists and Activities. |
| R-23 | Read the morning checklist aloud | [PARTIAL] | In-app read-aloud button. No voice command ("Hey OneSpace…"). |

## A3. Reminders (Remember tab)

| ID | Requirement | Status | Evidence / gap |
|---|---|---|---|
| RM-1 | First-class Reminders in Remember | [FULL] | Reminders screen. |
| RM-2 | Shared reminders that alert both partners | [FULL] | Audience me / partner / both. |
| RM-3 | On dismissal: done or needs follow-up + outcome notes | [FULL] | Follow-up requires a note. |
| RM-4 | Snooze: later today, next day, or a chosen day; outcome visible to both if shared | [FULL] | Per-recipient snooze, action log. |
| RM-5 | Link a reminder to its parent object | [PARTIAL] | Only checklist, calendar event, occasion. |
| RM-6 | Server-side due process, outbox and push delivery | [FULL] | Cron + outbox + FCM; push delivered on Android. |
| RM-7 | Respect working schedule, sleep and days off for notification timing | [NOT] | Only automatic gestures respect sleep; reminders and push do not. |
| RM-8 | (Implied by R-4) repeating reminders | [NOT] | No recurrence on reminders. |

## A4. Calendar and special dates

| ID | Requirement | Status | Evidence / gap |
|---|---|---|---|
| C-1 | One calendar both partners enter and see | [FULL] | Shared/private events. |
| C-2 | Collect dates from different sources | [PARTIAL] | Events, to-dos, days off, occasions, holidays. Missing: reminders, trips, Activity dates, planned experiences (all shown on Today). |
| C-3 | Tag/colour by whose event it is (not who entered it) | [FULL] | "For whom" field (me/partner/both). |
| C-4 | Month, week, day views like Google/iPhone | [PARTIAL] | Month grid, week **list**, day timeline. |
| C-5 | Share event by email | [FULL] | Opens mail app. |
| C-6 | Send a reminder about an event in-app / push | [FULL] | "Remind partner now". |
| C-7 | Phone calendar integration | [NOT] | Undecided (you left it open). |
| C-8 | Show archived via a history button at top | [FULL] | History control. |
| C-9 | Regional holidays captured automatically; selection in Settings → Preferences | [FULL] | US/EG feed + Saudi civic days, chosen in Settings. |
| C-10 | Halloween, Valentine's, NYE (cultural dates) | [PARTIAL] | Only where the country feed lists them; you accepted "keep it like that for now". |
| C-11 | Settings for birthdays, anniversary, special dates | [FULL] | Settings → Birthdays & special dates → Occasions. |
| C-12 | Work days off reflected on the calendar and respected in notification timing | [PARTIAL] | Shown on calendar; respected only by automatic gestures and checklists. |

## A5. Notes

| ID | Requirement | Status | Evidence / gap |
|---|---|---|---|
| N-1 | Smart rich-text note taking (formatting, checkboxes) with Flutter Quill | [FULL] | Notes 2.0. |
| N-2 | Pictures inside notes | [FULL] | Note images. |
| N-3 | Show archived via history button at top | [FULL] | Top actions. |
| N-4 | Remove old-notes migration | [FULL] | Not present. |
| N-5 | Evaluate integration with Android/iPhone notes | [NOT] | Not researched in code. |
| N-6 | Private notes about partner preferences (favourite food, movies, address, phone) | [PARTIAL] | Possible as free-form private notes; no structured "About Kandice" profile. |

## A6. Coordinate (Activities)

| ID | Requirement | Status | Evidence / gap |
|---|---|---|---|
| A-1 | Object = title + body; then add components around it | [FULL] | Title + optional details. |
| A-2 | Components: link, notes, compare, screenshot, due date, price, spec, reminder, steps, tags, mention, like/dislike, comments, status | [FULL] | 15 component types + reactions + chat + stages. |
| A-3 | Both partners edit the body with editing history | [FULL] | Activity revisions keep the original. |
| A-4 | Active, previous and audit trail | [FULL] | Active / Finished / Archived, full history. |
| A-5 | Countdown component | [FULL] | Countdown type, shown on Today. |
| A-6 | Tag inventory: reuse existing tags, add new | [FULL] | `space_tags`. |
| A-7 | Cancel, delete, mark done, remove a component, keep audit | [FULL] | Cancel / complete / archive / remove-and-restore. |
| A-8 | Like / dislike works | [FULL] | Per-user reactions (re-test on device). |
| A-9 | Chat shows **initials only**, not "You" / names | [DIFF] | Code deliberately shows "You" and the partner's full name, with initials in the avatar. |
| A-10 | @ typed in the message field suggests the partner | [FULL] | Inline suggestions in Activity chat. |
| A-11 | Keyboard must not cover the message field | [PARTIAL] | Code handles insets; needs device confirmation. |
| A-12 | Voice notes behave like WhatsApp/Messenger | [DIFF] | Tap mic → stop → preview → send. Not hold-to-record / slide-to-cancel. |
| A-13 | Partner is alerted to new messages (implicit in "don't forget to look at this") | [NOT] | Only mentions and replies notify. |
| A-14 | More reusable components and examples | [PARTIAL] | Contact, voice, countdown, map added; more possible. |

## A7. People & contacts

| ID | Requirement | Status | Evidence / gap |
|---|---|---|---|
| PC-1 | Contacts live in Remember | [FULL] | Remember → People & saved contacts. |
| PC-2 | Expand/edit icon opens the editor, not the originating Activity | [FULL] | Edit opens editor. |
| PC-3 | "From: [Activity]" clickable only for Activity-sourced cards; direct cards show "Created by" | [FULL] | Source-aware cards. |
| PC-4 | Collapsible cards | [FULL] | Implemented. |
| PC-5 | "Remember someone" and (+) open the card editor | [FULL] | Editor sub-page. |
| PC-6 | Notes field without "best time to reach them" hint | [PARTIAL] | Standalone editor says "Notes"; the Activity contact component still says "Notes / best time to reach them". |
| PC-7 | History icon replaces the top add-people icon | [FULL] | Top actions. |
| PC-8 | Soft delete with restore until retention period | [PARTIAL] | Soft delete and restore work; the 30-day purge never runs. |
| PC-9 | Import from phone; share vCard into OneSpace; save to phone | [PARTIAL] | Android only; iOS share extension missing. |
| PC-10 | Duplicate detection; company, role, website fields | [FULL] | Implemented. |
| PC-11 | Edit history limited to contacts (not Activities) | [FULL] | Scoped history (R43/R44). |
| PC-12 | Contacts findable via search (to stop asking "who is X?") | [NOT] | Not in global search. |
| PC-13 | Emergency contacts linked to Android/iPhone emergency features | [NOT] | Not built. |

## A8. A little love

| ID | Requirement | Status | Evidence / gap |
|---|---|---|---|
| L-1 | History behind a header icon with Sent / Received tabs, with date and time | [FULL] | Implemented. |
| L-2 | Tapping a gesture notification opens a type-specific pop-up | [PARTIAL] | Works from the in-app list; **a push tap opens the notification list**. |
| L-3 | Each partner adds own gestures and optionally a trigger | [FULL] | Custom gestures with optional ritual moment. |
| L-4 | Colourful, themed, aligned gesture blocks | [PARTIAL] | Themed cards; visual polish to confirm on device. |
| L-5 | Categories: Thank you, Lucky, Miss us, Miss home, Miss kids, Miss furry ones, I miss you | [FULL] | 14 types. |
| L-6 | Notification icon reflects gesture type | [PARTIAL] | In-app icon yes; the push itself is generic. |
| L-7 | Gesture management only in Settings; types as expandable cards with counters; every message editable; built-in + custom share one random pool | [FULL] | Settings → My love gestures. |
| L-8 | "Create my own gesture" at the top | [FULL] | Present. |
| L-9 | Remove "x messages · tap to send" hints | [PARTIAL] | Verify on device (counts shown in management view). |
| L-10 | Rituals in a separate settings tab; remove duplicated consent setting | [PARTIAL] | Separate "Thoughtful rituals" entry; consent still also lives in Profile. |
| L-11 | Replace automated gestures with smart self-reminders (last sent, work days, holidays, days off, occasions, mood ≤3 if shared) | [PARTIAL] | Self-reminders exist at **fixed** 9/18/21 h; none of the smart conditions. Old rituals still present. |
| L-12 | No consent needed (it's a feature) | [DIFF] | Remaining automatic rituals still require recipient consent (they are dormant). |
| L-13 | One "A little love" square on Today | [FULL] | Explore tile. |
| L-14 | Messages she sees when she wakes up (scheduled message) | [NOT] | No scheduled letter/gesture send; only dormant automatic morning ritual. |

## A9. Daily check-ins

| ID | Requirement | Status | Evidence / gap |
|---|---|---|---|
| K-1 | Two square buttons: Record my feeling / Check on my partner | [FULL] | Implemented. |
| K-2 | Record: rating + on my mind + grateful for; share or keep private | [FULL] | One per day. |
| K-3 | Check on partner: partner replies with rating + on mind + something to talk about | [FULL] | 7-day expiry, acknowledgements. |
| K-4 | Remove "How is your heart today?" | [FULL] | Not present. |
| K-5 | Readable, distinguishable log fitting the new logic | [PARTIAL] | Redesigned; final visual QA open. |
| K-6 | Automatic morning check-in / after-work / goodnight prompts | [NOT] | Superseded by self-reminder idea; not built for check-ins. |

## A10. Shared experiences and games

| ID | Requirement | Status | Evidence / gap |
|---|---|---|---|
| E-1 | One list each: Movies, TV, Music, Books & articles, Games, Others as blocks | [FULL] | Category blocks. |
| E-2 | Filters behind a filter icon at top | [FULL] | Top actions. |
| E-3 | Focus on name and platform; drop "Planned for / Enjoyed on" | [DIFF] | Dates still stored and shown (they feed Today's agenda). |
| E-4 | Mark watched directly from the card (movies and TV only) and rate from the card | [FULL] | Card actions. |
| E-5 | Watch / Play / Open button by type | [PARTIAL] | Movies/TV "Watch"; everything else "Open" (music is not "Play"). |
| E-6 | Fix "permission denied for shared_experience_reviews" | [FULL] | RLS fixed (confirm in APK). |
| E-7 | Edit history at experience level, limited to experiences | [FULL] | History at top. |
| E-8 | New archive behaviour | [FULL] | Archived history. |
| E-9 | Posters, thumbnails, genres, genre filter, richer metadata | [NOT] | No schema fields. |
| E-10 | Share from Netflix/Spotify etc. into OneSpace | [PARTIAL] | Android share-in saves the link; no metadata parsing. |
| E-11 | Games as external invitation link + review + comments | [FULL] | Games category. |
| E-12 | Discuss and share insights | [FULL] | Comments (R45 edit/retract), reviews, mutual picks. |

## A11. Memories and scrapbook

| ID | Requirement | Status | Evidence / gap |
|---|---|---|---|
| M-1 | Daily selfie can take or upload a photo | [FULL] | Camera and gallery. |
| M-2 | Fix "permission denied for table memories" | [FULL] | Fixed (confirm on device). |
| M-3 | Tags: who is in the photo, where, other tags; searchable | [PARTIAL] | Tags and search inside Memories; **not in global search**. |
| M-4 | Scrapbook Studio: designed templates, fill slots, personalise, export | [PARTIAL] | 4 templates, PNG export (Android). You asked to be impressed; the library is small. |
| M-5 | One partner starts a scrapbook and invites the other | [FULL] | Invite / accept / decline. |
| M-6 | Collages and layouts (centre photo with handwriting, tilted, overlapping/switching) | [PARTIAL] | Overlapping stack, collage and Polaroid exist; no handwriting style; no tilted pair. |
| M-7 | Share photos from the gallery | [FULL] | Gallery picker. |
| M-8 | Shared memory deletion requires the other partner's confirmation | [NOT] | Archive only; no mutual-delete workflow (you marked it unsettled). |

## A12. Occasions, holidays and gifts

| ID | Requirement | Status | Evidence / gap |
|---|---|---|---|
| O-1 | Plan Christmas, Halloween, NYE, Valentine's and both birthdays | [FULL] | Occasions of any kind, yearly. |
| O-2 | Reminders early enough to shop; financial reminder the month before (salary) | [PARTIAL] | Save/research/order/prepare suggestions with fixed lead days; no salary-month logic. |
| O-3 | Your timing rule: 2nd-half occasion → start of last week of previous month; 1st-half → one month earlier | [NOT] | Not implemented. |
| O-4 | Put all ideas and options in one place: name, link, price, delivery date, ratings, my score | [FULL] | Budget items. |
| O-5 | Select items, see total, highlight late arrivals | [FULL] | Combination planner with late-arrival flag. |
| O-6 | Save a combination as a proposed list | [FULL] | Proposals. |
| O-7 | Track orders after purchase | [PARTIAL] | Manual order status, number and tracking link. |
| O-8 | Returns and finding alternatives | [FULL] | Return state/reason; reopen comparison. |
| O-9 | Budgeting that is real budget planning | [PARTIAL] | Planned / reserved / spent / wish totals per currency; no cash-flow plan by salary month. |

## A13. Trips and travel

| ID | Requirement | Status | Evidence / gap |
|---|---|---|---|
| T-1 | Planning: who, destination, preferred/flexible dates | [PARTIAL] | Title, origin, destination, dates/flexible, visibility; no "who travels" field. |
| T-2 | Search flights (Google Flights) | [DIFF] | Opens Google Flights externally; no in-app results. |
| T-3 | Save search results for comparison | [FULL] | Flight options. |
| T-4 | Purchase, save ticket emails | [PARTIAL] | Upload PDFs/images; no email import. |
| T-5 | Reminders: check-in, leave time, download offline media/maps, safe-flight wishes | [PARTIAL] | Prep checklist templates include these as tasks; no timed reminders or wishes. |
| T-6 | Documents: tickets, reservations, seats, hotel, extra luggage receipt, pet documents, visa, airport contact | [PARTIAL] | Kinds: boarding pass, itinerary, ticket, receipt, photo, other. No visa/pet/seat types; a contact card can't be attached to a trip. |
| T-7 | Documents organised, visual, searchable | [PARTIAL] | Listed per trip and searchable by title. |
| T-8 | Documents **always available offline** | [NOT] | Online only. |
| T-9 | Countdown to next vacation, time since we last met, history of visits | [PARTIAL] | Manual counters; trips don't update them; no visit history. |
| T-10 | Watchlist for the trip | [PARTIAL] | Reminder in checklist template; no link to Experiences. |

## A14. Today dashboard and navigation

| ID | Requirement | Status | Evidence / gap |
|---|---|---|---|
| D-1 | Navigation Today · Remember · Coordinate · Connect · World | [FULL] | Main shell. |
| D-2 | "One Life, Two Places" tagline visible (was reported missing once) | [FULL] | On Today; the startup screen uses a different variant. |
| D-3 | "Welcome back, [first name]"; first name also on sign-in | [FULL] | Implemented. |
| D-4 | Partner named by preferred labels, several labels at random | [FULL] | `partner_labels`. |
| D-5 | Merge relationship + clocks; remove headers "Our clocks", "Long distance…", "same local time" | [FULL] | Removed. |
| D-6 | Living-arrangement selection: icon, dropdown, simple | [DIFF] | Two-segment switch in Settings; only 2 of the 3 states you named. |
| D-7 | Together hides clocks/weather but keeps counters, with a placeholder | [FULL] | "Together under one roof" panel. |
| D-8 | Hide counters when not set; allow reset of last/next meeting | [FULL] | Clear buttons. |
| D-9 | Weather side by side: city, region, country, temp, hint, high/low, rain; no repeated name | [PARTIAL] | Verify layout on device. |
| D-10 | Needs attention, Coming up, Recent discussions in the same container style, collapsible, with counters and collapsed hints | [FULL] | Implemented. |
| D-11 | Recent discussions must not repeat the same Activity | [FULL] | Grouped per Activity. |
| D-12 | Coming up shows the next 7 days | [PARTIAL] | Works, but excludes Reminders and recurring routines. |
| D-13 | Needs attention business logic (agreed with you) | [PARTIAL] | Rules exist (see Handbook §5.2); excludes Reminders, letters and routines. |
| D-14 | Remove "Our day at a glance" | [FULL] | Not present. |
| D-15 | Explore our space: square cards reflecting what exists, plus Shared experience square | [PARTIAL] | 9 square tiles; Reminders, Occasions, People and Trips are missing. |
| D-16 | Notification bell at top | [FULL] | Bell. |
| D-17 | Settings gear 2nd from right; then "…" menu so the tagline is not cut | [FULL] | ⋮ menu (Settings, Search, Language). |
| D-18 | Remove upcoming events / dues / recent notes from Remember | [FULL] | Remember is a module list. |
| D-19 | Clock should stay in sync while the screen is open | [FULL] | Minute timer refresh. |
| D-20 | Today should not show "Shared goals" (never requested) | [DIFF] | Goals module exists in Connect and the home snapshot. |

## A15. Global behaviours

| ID | Requirement | Status | Evidence / gap |
|---|---|---|---|
| G-1 | Mostly mutual space; some "Only me" features; privacy choice "Only me / Both of us" | [FULL] | Shared/private + view-only grants. |
| G-2 | Partner edits/deletes another's content: show crossed out in red | [NOT] | History kept, but no visual red strike-through of partner changes. |
| G-3 | Completed steps crossed out and italic | [PARTIAL] | Strikethrough used; italics inconsistent. |
| G-4 | History and filters (incl. archived) at top of every screen | [PARTIAL] | 9 screens use the standard bar; To-do, Calendar, Check-ins, Letters, Gestures differ. |
| G-5 | Every item: edit, delete, cancel, restore (respecting rules) | [PARTIAL] | Main records yes; child records vary. |
| G-6 | Every action logged: who, what, when | [PARTIAL] | Broad metadata history; some child actions not logged. |
| G-7 | @mentions work in every field and component | [PARTIAL] | Main records yes; full-name matching only; separate button outside chat. |
| G-8 | Every entry, component and object searchable | [PARTIAL] | Contacts, checklist items, chat, comments and check-ins are missing. |
| G-9 | Text/background contrast in all themes and modes | [PARTIAL] | Automated contrast tests; manual pass outstanding. |
| G-10 | Connect features so one idea travels through its lifecycle without re-entry | [PARTIAL] | Activity→Occasion, Note links, Trip→checklist, Reminder→source. No Activity→Calendar, Activity→Trip, Experience→Trip watchlist. |
| G-11 | Don't keep kicking me out while using the app | [FULL] | 30-min idle / 5-min background lock (confirm on device). |
| G-12 | Simplify sign-in: one screen, fingerprint/PIN or password, email remembered | [DIFF] | One screen, but biometrics only unlock an *existing* session; after sign-out a password is required (a sound security decision). |
| G-13 | Biometric stopped working (bug) | [PARTIAL] | Rewritten; needs device confirmation. |

## A16. Language, themes and settings

| ID | Requirement | Status | Evidence / gap |
|---|---|---|---|
| S-1 | Each partner chooses app language; menus and notifications localised; content not translated | [PARTIAL] | Per-user locale; ≈25% of UI and no push text localised. |
| S-2 | Selectable themes (neutral preferred: black, white, grey, blue) | [FULL] | 4 palettes, light/dark. |
| S-3 | Two themes for together vs long distance | [NOT] | Theme does not follow relationship mode. |
| S-4 | One Settings place; Profile separate | [PARTIAL] | Settings exists; several items duplicated in Profile. |
| S-5 | Preferred names and love-gesture lists managed from Settings | [FULL] | Implemented. |
| S-6 | Temperature unit (US/metric) in preferences | [FULL] | Implemented. |
| S-7 | Preferred language accessible from anywhere | [FULL] | ⋮ → Language. |
| S-8 | Working schedule and sleep set once; features avoid those times | [PARTIAL] | Stored; only gestures and checklists use them. |
| S-9 | Better backgrounds and per-theme icons (not a technical asset editor) | [PARTIAL] | Seasonal accents; limited per-theme icons. |
| S-10 | Preset per-record layouts for notes/lists (photo + notes, side by side, etc.) | [NOT] | Only in Scrapbook (deferred). |

## A17. Platforms, integrations, AI, voice and infrastructure

| ID | Requirement | Status | Evidence / gap |
|---|---|---|---|
| X-1 | Android and iOS | [PARTIAL] | Android previews only. |
| X-2 | No public go-live; test privately first | [FULL] | Preview APKs via GitHub releases. |
| X-3 | Integrate with existing apps by sharing in; don't recreate them | [PARTIAL] | Android share-in to Activities and Experiences; not to Notes, Trips or Reminders. |
| X-4 | Amazon/Target/Walmart link → right list or task | [PARTIAL] | User picks the destination; no auto-classification. |
| X-5 | Push notifications via your Firebase | [FULL] | Working (generic content). |
| X-6 | Voice search / commands / Siri; "read me the morning checklist" by voice | [NOT] | In-app TTS only. |
| X-7 | AI assistance level 2 (summaries, extraction, criteria, itinerary help) | [NOT] | Not started. |
| X-8 | Server relocation (deferred by you) | [DIFF] | Still Seoul, as you decided. |
| X-9 | Security, privacy, database corrections | [PARTIAL] | Strong RLS; leaked-password protection off; migration history drift. |
| X-10 | Partner pairing: create household and invite (open question about better ways) | [FULL] | 48-hour single-use code. No QR or link-based invite. |

## A18. Local testing checklist (from the RoadMap)

| ID | Test | Status | Note |
|---|---|---|---|
| Q-1 | Install and launch Android build on a test phone | [FULL] | 0.1.417 installable. |
| Q-2 | Install and launch iOS build | [NOT] | No iOS build. |
| Q-3 | First trial on your own phone | [FULL] | Done (from your feedback history). |
| Q-4 | Create household and confirm it appears | [FULL] | Done (live data shows one space). |
| Q-5 | Invite partner and confirm the invitation reaches her | [FULL] | Two members in live data. |
| Q-6 | Accept and confirm both connected | [FULL] | Two members, two push devices. |
| Q-7 | Close and reopen; connection persists | [PARTIAL] | Expected; not formally recorded. |
| Q-8 | Pair one Android with one iPhone | [NOT] | Blocked by Q-2. |
| Q-9 | Record pairing problems / clarity | [PARTIAL] | No written test record. |
| Q-10 | Share private build with your wife | [PARTIAL] | Two Android devices registered; both profiles show Asia/Riyadh, so it looks like two test phones rather than Kandice's own. |

## A19. Totals

| Status | All items (204) | Product requirements only (188) |
|---|---|---|
| Fully | 105 (51%) | 99 (53%) |
| Partial | 68 (33%) | 60 (32%) |
| Different | 10 (5%) | 10 (5%) |
| Not built | 21 (10%) | 19 (10%) |

> "All items" includes the 6 original problem statements (A1) and the 10 local-testing checks (A18). The R45 document counted 179 consolidated items with 60% Fully. My register is more granular (your later UI feedback is listed item by item) and uses a stricter test, giving **53% Fully** for product requirements.


# Part B: Review of "OneSpace_Roadmap_Reviewed_Requirements_R45"

## B1. What the document does well

- **Traceability:** 179 numbered requirements (OS-001…OS-179) grouped in 19 domains, each with evidence pointers. This is a good structure to keep.
- **Honest release boundary:** it correctly states that R45 is not in APK 0.1.417 and that "fully" does not mean device-tested.
- **Respects your later decisions:** legacy lists retired, games as links, server move deferred, import/export instead of contact sync.
- **Sensible priority tiers (P0–P3)** at the end, with privacy and device acceptance first.

## B2. Where it is too generous

The main weakness is the definition of **"Fully implemented"**. In practice it means "an identifiable screen and table exist", not "it behaves the way Ahmed asked". The builder is also grading its own work. Items I would reclassify:

| R45 item | R45 says | I say | Why (from the code) |
|---|---|---|---|
| OS-005 Living together / apart / LDR | Fully | Differently | UI writes only 2 of 4 modes; "apart, same time zone" cannot be chosen. |
| OS-022 Needs attention | Fully | Partial | Excludes first-class Reminders, routines and letters; dead "urgent" branch for to-dos. |
| OS-023 Coming up (7 days) | Fully | Partial | Excludes Reminders, holidays, days off and recurring routines. |
| OS-042 Recurrence time zone and holiday exclusions | Fully | Partial | Holidays hard-coded US federal only; typed IANA zone. |
| OS-055 Server-side reminder delivery | Fully | Partial | No recurrence, no quiet hours, no source re-validation. |
| OS-070 Activity conversation | Fully | Partial | Plain messages never notify; the chat shows "You"/full name although you asked for initials. |
| OS-128 Preparation-phase reminders | Fully | Partial | Fixed lead days; your timing rule not implemented. |
| OS-144 Push through Firebase | Fully | Partial | Generic, unlocalised body; push tap opens the list, not the item. |
| OS-157 Central settings separate from profile | Fully | Partial | Weather city, schedule, consent and language duplicated in Profile. |
| OS-171 Preserve records through RLS | Fully | Fully (with a caveat) | RLS is solid, but 11 live migrations are missing from the migration history. |
| OS-097 Self-reminders | Fully | Partial | Fixed 9/18/21 h; none of the smart conditions you described. |

## B3. What it missed entirely

1. **Menstrual-cycle tracking** and **medication times**: in your first page of requirements, absent from the 179 items.
2. **Recurring reminders**: the most important missing capability for daily life.
3. **Silent Activity chat**: the core collaboration loop does not alert the partner.
4. **Contacts missing from global search**: it notes search is partial but doesn't name the gap most relevant to your original problem.
5. **Quiet hours for reminders and push** across time zones.
6. **Migration-history drift** (0095–0105 applied but not recorded).
7. **Generic push content.**
8. **"Messages to see when she wakes up"** (scheduled letters/gestures).
9. **Stale and duplicated UI copy** (Connect hub says selfies are "planned"; two taglines; developer panel in Profile).
10. **Goals module**: built without request and not discussed.
11. **Chat identity and voice-note behaviour** that contradict your explicit feedback.
12. **Contact purge never runs** despite a 30-day retention date.
13. **Arabic coverage not quantified** (≈25%).

## B4. Overall verdict on the R45 document

It is a **useful, well-structured traceability register** and a fair *engineering* inventory. As a *business acceptance* document it **overstates completion by roughly 7 percentage points overall**, and by much more in the areas that matter most for daily use (alerts, reminders, search). It also frames gaps softly ("needs device review") where the code shows a definite gap. Keep its ID scheme and P0–P3 tiers. Replace its "fully" test with **"does the behaviour match Ahmed's latest instruction, end to end, including alerts?"**, and add a severity per gap.


# Part C: How we continue: working agreement and plan

## C1. Working agreement (what I propose)

| Topic | Proposal |
|---|---|
| Approval | I never change code, the database or settings without your explicit "go" on a written scope. Reviews are read-only. |
| Source control | One branch and one Pull Request per iteration. `main` changes only when you approve the merge. |
| Database | Every change is a numbered migration file **and** a recorded Supabase migration (fixes the drift). Destructive changes are always shown to you first. |
| Builds | Keep the existing policy: CI verification on every push, one signed APK per approved batch. |
| Acceptance | Each iteration ships with a short two-phone test script (10–20 steps) written for you, not for developers. |
| Single source of truth | The Handbook (this baseline) + a Decision Log + a Backlog stored in this claude.ai Project, updated each iteration. |
| Severity | Every finding is rated Critical/High/Medium/Low and fixed in that order unless you decide otherwise. |
| Language | Business explanations in plain language; technical notes in a separate appendix. |

## C2. Decisions I need from you before building

1. **Automatic love rituals:** retire them (self-reminders only) or keep them as an explicit opt-in? *My recommendation: retire, and make self-reminders smart.*
2. **Shared Goals:** remove, hide, or repurpose (e.g. "savings for our next visit")?
3. **Relationship mode:** confirm three choices: Together · Apart, same time zone · Long distance.
4. **Edits to shared items:** should the partner be notified when a shared event, trip or reminder *time* changes? *Recommendation: yes, for date/time changes only.*
5. **Quiet hours default:** hold non-urgent alerts during the recipient's sleep window and deliver at wake time? *Recommendation: yes, with an "urgent" override.*
6. **Push privacy level:** show type and partner name (e.g. "Kandice sent you a letter") or keep it generic? *Recommendation: type + name, never content.*
7. **Chat identity:** do you still want initials only instead of "You"/name?
8. **Mutual deletion of shared memories:** decide now or keep archive-only?
9. **Cycle tracking:** do you still want it? It is sensitive health data, so it needs a private-by-default design.

## C3. Proposed iteration plan (from the code, in priority order)

| Iteration | Theme | Scope |
|---|---|---|
| **R46** | Baseline hygiene (no visible change) | Record missing migrations; enable leaked-password protection; remove stale copy; one tagline; hide developer panel; fix "last met today" text; align to-do priority scale. |
| **R47** | Reminders that work for real life | Recurring reminders; quiet hours & days-off awareness; show recipient's local time; stop alerts for cancelled/archived sources; Reminders + today's routines in Today. |
| **R48** | Never miss a message | Notify on every Activity message (batched); type-specific, localised push with deep links (incl. gesture pop-up); edit notifications for date/time changes. |
| **R49** | Find anything | Contacts, checklist items, chat, comments, photo tags in global search; one shared @-autocomplete with first-name/label matching. |
| **R50** | One calendar | Calendar shows reminders, trips, Activity dates, experiences as toggleable layers; true week grid; optional pre-event alert. |
| **R51** | Travel-ready | Offline encrypted documents, travel-day card on Today, check-in/leave reminders, more document types, trip end updates "last met". |
| **R52** | Thoughtful love & occasions | Smart self-reminders (last sent, schedule, days off, shared mood ≤3); your occasion timing rule + salary month; three-mode relationship selector. |
| Later | Expansion | Complete Arabic; settings consolidation; posters/genres; scrapbook templates; iOS; AI level 2; voice; account deletion/export. |

Each iteration is roughly one focused build plus one APK. R46–R48 alone would remove most of the "dropped request" risk that motivated OneSpace.

## C4. What I already have and what I need from you

| Item | Status |
|---|---|
| GitHub repository access | Connected (read and push), private repo `BoyofKay/OneSpace`. |
| Supabase access | Connected to project OneSpace (Seoul); read-only queries used so far. |
| Firebase | Not needed for review. Push credentials already live in Supabase secrets; only needed if we change the Firebase project. |
| Phones | Only you can install APKs and run two-phone tests. I will write the test scripts. |
| Your input | Answers to the 9 decisions in C2, and your go-ahead to start R46. |
