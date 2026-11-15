> Generated 15 Nov 2026 by Claude from code ae0870b (R45). PDF version shared with Ahmed. Later decisions: see DECISION_LOG.md.

# 1. How to read this handbook

This handbook describes OneSpace **as it is built today**. Every statement comes from the source code in GitHub (`BoyofKay/OneSpace`, main branch, commit `ae0870b`, tagged R45) and from the live Supabase database (`ugwrpeduzyzrujkizqfo`, Seoul). It does not repeat what was promised in chat or written in prompts. Where the code and the earlier discussion disagree, the code wins and the difference is called out.

> **Scope of evidence.** I read the Flutter app (≈27,600 lines in 150+ Dart files), all 105 schema files, the database as deployed (tables, RLS, triggers, functions, scheduled jobs, storage buckets), the push Edge Function, the CI workflow and the GitHub release history. I did not run the app on a phone, so anything about how a screen *looks* on a device is inferred from layout code. Nothing in the code or the database was changed during this review.

**Status labels used throughout**

| Label | Meaning |
|---|---|
| [FULL] | Works end to end in code and database. Still needs two-phone testing. |
| [PARTIAL] | Some of the workflow exists; a meaningful part is missing. |
| [DIFF] | A feature exists but behaves differently from what was asked. |
| [NOT] | No working implementation found. |
| [CRIT] / [HIGH] / [MED] / [LOW] | Severity of a finding (defect, open loop, risk). |

**Release boundary.** The latest installable Android preview is **0.1.417** (built 14 Nov 2026 from commit `ac6e911`). The R44 and R45 changes (expanded action history, editable/retractable Experience comments) are in the source and database but are **not in any APK yet**. If you test on a phone today you are testing 0.1.417, not R45.


# 2. Executive summary: the current business position

## 2.1 What OneSpace is today

OneSpace is a private, two-person Android app (Flutter, iOS not yet packaged) for a couple who live apart or together. It has **five tabs (Today, Remember, Coordinate, Connect, World)**, **19 functional modules**, **66 database tables**, **3 scheduled background jobs** and **1 push-delivery service**. It is a well-secured, feature-wide prototype. Breadth is ahead of depth: almost every idea from the roadmap has a first version, but few modules are finished to the level a daily user would rely on without friction.

## 2.2 Maturity scorecard

| Module | Maturity | One-line verdict |
|---|---|---|
| Pairing, sign-in, lock | Good | Secure and simple; biometric only unlocks an existing session (by design). |
| Today dashboard | Fair | Rich, but "Needs attention" and "Coming up" ignore first-class Reminders. |
| Calendar | Fair | Month / week list / day views; does not show Reminders, Trips, Activities or Experiences that Today shows. |
| To-do & Checklists | Fair | Strong recurrence engine; technical UX (typed timezones, typed dates); recurring lists never surface in Today. |
| Reminders | Fair | Server-side delivery works, but **no recurrence** and **no quiet hours**. |
| Notes 2.0 | Good | Quill rich text, images, links to other records, conflict protection. |
| Occasions & gifts | Good | The deepest module (budget, gift comparison, orders, returns). Salary-month timing rule not implemented. |
| People & contacts | Fair | Good card model and phone import/export, but **not included in global search**. |
| Coordinate (Activities) | Good | The strongest workflow in the app. Plain chat messages do **not** notify the partner. |
| Letters | Good | Drafts, sending, replies, read receipts. |
| A little love | Fair | Rich gesture library; self-reminders use fixed clock times; auto-rituals effectively dormant. |
| Check-ins | Good | Clear two-path model (record feeling / check on partner), 7-day expiry, acknowledgements. |
| Shared experiences & games | Fair | Library, mutual picks, ratings, comments; no posters, genres or metadata. |
| Memories & Scrapbook | Fair | Camera/gallery selfies, photo tags, 4 scrapbook templates, PNG export. |
| Trips | Fair | Itinerary, flight comparison, documents, prep checklists; **no offline documents**, no trip reminders. |
| Notifications & push | Fair | Push works on Android; every push says the same generic sentence and opens the list, not the item. |
| Search & mentions | Partial | Search misses contacts, checklist items and comments; @mentions match the full display name only. |
| Settings, themes, language | Fair | 4 palettes, light/dark, seasonal; **about 25% of UI text is translated to Arabic**. |
| Goals | Orphan | Built and linked in Connect, but never requested by you. |

## 2.3 The ten things that matter most

1. [HIGH] **Reminders cannot repeat.** The `reminders` table has no recurrence. Medication times, laundry, gas, pick-ups (all in your original brief) cannot be set up once. Recurrence exists only for checklists.
2. [HIGH] **Plain Activity chat messages are silent.** The partner gets an alert only for an @mention or a direct reply. A message like "don't forget to look at this" creates no notification and no push.
3. [HIGH] **Reminders and recurring checklists are not in Today.** "Needs attention" and "Coming up together" never list first-class Reminders, and recurring checklists (no target date) never appear.
4. [HIGH] **Contacts are not searchable globally**, although remembering people was one of the first problems you described.
5. [HIGH] **Push messages are generic and do not deep-link.** Every push reads "You have a new update in your shared space." Tapping opens the notification list, not the gesture, reminder or item.
6. [MED] **No quiet hours for reminders or push.** Only the (dormant) automatic gestures respect sleep and days off. A 3 a.m. shared reminder will buzz your partner.
7. [MED] **Arabic coverage is thin.** About 288 UI strings go through the translator against about 862 hard-coded English labels.
8. [MED] **Database migration history has drifted.** Schema files 0095–0105 (R30–R44) are applied to the live database but are not recorded in Supabase's migration history. A rebuild or branch from history would lose them.
9. [MED] **Occasion timing does not follow your rule.** You asked for reminders at the start of the last week of the previous month (or a month early, depending on which half of the month the occasion falls). The code uses fixed lead days (60/30/14/3) at 9:00 a.m.
10. [MED] **The relationship-mode model was simplified.** The database supports four modes, but the screen offers only "Living apart" and "Together". "Apart in the same time zone" cannot be chosen, so two partners in Riyadh are labelled `apart_different_tz` (this is the case in your live data today).

> **Bottom line.** The foundation (security, data model, audit trail, privacy rules) is better than typical for a prototype at this stage. The next phase should not add new modules. It should **close the loops** between existing ones: reminders that repeat and respect sleep, alerts that reach the right screen, and one calendar and one Today that show everything. The rest of this handbook gives the detail.


# 3. Product overview

## 3.1 Purpose and users

OneSpace is "One Life, Two Places". It is a private shared space for exactly **two people** who form one couple ("space"). It addresses remembering details of each other's lives, coordinating across time zones, following through on requests, planning gifts and trips, and staying emotionally connected. It deliberately does not replace WhatsApp, Netflix, Spotify or Amazon. It captures links and decisions from them.

**Roles.** There are no admin roles. Both partners are equal members. Every record has a **creator**, and many have a **visibility**: *Shared* (both of us) or *Private* (only me). Some records also have an **assignee** or **"for whom"** person (calendar events, to-dos, reminders).

## 3.2 Navigation map (as built)

| Tab | Screen / module | Opened from |
|---|---|---|
| **Today** | Greeting, clocks & weather (or "Together under one roof"), meeting counters, Needs attention, Coming up (7 days), Countdowns, Recent discussions, Explore grid (9 tiles) | App start |
| **Remember** | Calendar · To-do and Checklists · Reminders · Notes · Occasions & surprises · People & saved contacts | Remember tab list |
| **Coordinate** | Activities list (Attention / Active / Finished / Archived), Activity detail with components, comparison, decisions, chat, voice | Coordinate tab |
| **Connect** | Letters · A little love · Daily check-ins · Shared experiences · Memories (+ Scrapbook Studio) · Shared goals | Connect hub list |
| **World** | Trips & journeys (itinerary, flights, documents, prep checklists, conversation) | World hub list |
| **Top bar** | Notification bell · ⋮ menu (Settings, Search our space, Language) · Profile | Every tab |

The Explore grid on Today offers 9 shortcuts: Activities, Calendar, To-do and Checklists, Notes, Letters, Memories, Check-ins, A little love, Shared experiences. It does **not** offer Reminders, Occasions, Contacts or Trips. With 9 tiles in a 2-column grid, the last row is half-empty.

## 3.3 The privacy model in one page

- **Space membership.** One account can belong to only one space (`space_members.user_id` is unique). A space holds at most two people. Every table is protected by row-level security that checks membership.
- **Shared vs private.** Shared records are visible and (usually) editable by both partners. Private records are visible only to the creator.
- **View-only grants.** A private Task, Note, Calendar entry, Memory or List can be shared *read-only* with the partner, and the grant can be revoked (`object_shares`, `set_object_share`).
- **Immutable visibility.** A to-do's visibility cannot change after creation, so stale private data cannot leak through realtime streams.
- **Soft delete.** Application accounts cannot hard-delete most records. They archive, cancel, retract or "remove (kept in history)".
- **Audit trail.** A metadata-only history (`record_action_history`) records *who*, *what action* and *which fields* (not the content) for notes, to-dos, goals, memories, events, reminders, occasions, experiences, trips, contacts, check-ins and Experience comments. Activities, components, occasions, trips and contacts also keep full revision tables.
- **Storage.** Five private buckets (activity photos, activity voice, trip documents, memory photos, note images). There are no public URLs. Files are opened through short-lived signed links (e.g. 90 seconds for travel documents).


# 4. Platform, architecture and data

## 4.1 Technology stack

| Layer | What is used | Notes |
|---|---|---|
| App | Flutter 3.50 (Dart), Material 3 | Android signed previews; iOS folder exists but no build, share extension or Firebase config. |
| Backend | Supabase (Postgres 17, Auth, Realtime, Storage, Edge Functions, pg_cron, pg_net, Vault) | Region ap-northeast-2 (Seoul). |
| Push | Firebase Cloud Messaging HTTP v1 | Used only for push delivery. |
| Weather | Open-Meteo geocoding + forecast | No API key; called from the phone. |
| Holidays | Nager.Date API v4 (`nagerholidays.com`) | US and Egypt feeds; Saudi Founding/National Day are hard-coded date-only. |
| Rich text | flutter_quill 11.6 | Notes 2.0. |
| Voice | `record` + `just_audio` | Activity voice notes (m4a). |
| Device | local_auth (biometric/PIN), flutter_secure_storage, image_picker, url_launcher, native share/contact/TTS bridges | Android method channels for share-in, contacts and checklist read-aloud. |
| CI/CD | GitHub Actions: verify (analyze + 244 unit/widget tests) and a separate signed-APK release on an explicit marker | Firebase config injected from a GitHub secret at build time. |

## 4.2 Live data snapshot (15 Nov 2026)

There are two profiles, one space, both members on Android, both profiles in time zone Asia/Riyadh with locale English, relationship mode "apart, different time zones", and no meeting dates set. Record counts: 10 Activities, 9 to-do/checklists, 1 note, 0 calendar events, 1 reminder, 1 occasion, 1 trip, 4 memories, 8 experiences, 2 contacts, 1 goal, 1 letter, 1 daily check-in, 44 notifications. 9 push messages have been delivered successfully. No automatic gesture schedules are enabled, and neither profile has sleep times set.

## 4.3 Background jobs (pg_cron)

| Job | Schedule | What it does |
|---|---|---|
| `onespace-due-reminders` | every 5 min | Finds reminder recipients whose `next_alert_at` has passed (pending or follow-up), writes a "Reminder: …" notification, marks it notified. Max 100 per run. |
| `onespace-consented-gestures` | every 5 min | Sends automatic morning / after-work / goodnight gestures when the recipient opted in and has a full sleep window and time zone. |
| `onespace-fcm-push-delivery` | every 1 min | Calls the Edge Function `onespace-push-delivery` with a Vault secret. The function claims up to 25 queued pushes, sends them through FCM and marks each sent, retry or invalid. |

## 4.4 Server functions the app calls (RPCs)

`create_space`, `create_invitation`, `accept_invitation`, `revoke_pending_invitation`, `get_home_snapshot_v2`, `get_remember_overview`, `onespace_my_attention`, `onespace_coming_up`, `record_activity_decision`, `respond_to_reminder`, `save_occasion_proposal`, `create_trip_preparation_checklist`, `create_scrapbook`, `invite_scrapbook_partner`, `respond_scrapbook_invite`, `set_object_share`, `register_push_device`, `disable_push_device`. Two service-only functions (`claim_push_outbox`, `complete_push_delivery`) are correctly *not* executable by app users.


# 5. Module handbook: user guide, rules and edge cases

Each module follows the same pattern: **what it is for → how to use it → business rules → automations and alerts → edge cases and gaps.**

## 5.1 Account, sign-in, pairing and privacy lock

**How to use.** Create an account with email and password (confirmation email; can be resent). Sign in. On Today, either **Create our space** or paste a partner's **invitation code** and **Join**. The creator sees "Members 1/2" and **Create invitation**. The code is high-entropy, valid **48 hours**, single use. Creating a new code revokes the old one, and the creator can revoke it explicitly.

**Business rules**
- One account belongs to one space only. A space holds at most two members.
- The phone remembers **one** email (the last successful account). There is no account switcher.
- **Privacy lock:** after **30 minutes idle** or **5 minutes in the background**, the app shows the sign-in screen over the live session. A fingerprint or phone PIN (Android OS prompt) reopens it, or the password does.
- Biometrics only **unlock an existing session**. After a real sign-out, the password is required (biometrics are never used as server credentials).
- An inactivity lock never unregisters push. A real sign-out disables this phone's push device first.
- Password change (8+ characters) is in Profile. Password recovery by email exists. Account deletion does not.

**Edge cases and gaps**
- [MED] Supabase "leaked password protection" is still off (security advisor warning).
- [LOW] If the network is slow at start, the app shows "Opening your secure space…" with Retry. The startup tagline reads "One Life. Two Places. One Space." while Today shows "One Life, Two Places" (two variants of the brand line).
- [LOW] Profile exposes a developer panel ("Seoul API round trip", "Stop monitoring") that ordinary users will not understand.

## 5.2 Today

**What it shows, top to bottom**
1. "Welcome back, [first name]" and "Your space with [partner label]".
2. Brand tagline and a small seasonal theme preview.
3. **Relationship panel.** When *apart*: one clock per partner (device time zone, DST-aware, refreshes every minute) plus the selected city's weather (temperature, condition, high/low, rain %). When *together*: "Together under one roof".
4. **Meeting counters** (only if dates are set): "Last time we met · N days ago" and "Our next meeting · N days to go".
5. **Needs attention** (server function `onespace_my_attention`, top 20). Each item can be opened or snoozed for yourself only.
6. **Coming up together** (server function `onespace_coming_up`, today plus 6 days).
7. **Our countdowns** (from Activity *countdown* components).
8. **Recent discussions** (one row per Activity, latest message plus message count; collapsible).
9. **Explore our space** grid (9 tiles).

**Needs attention: exact rules (score 0 = most urgent)**

| Source | Included when | Reason text | Score |
|---|---|---|---|
| Activity | not archived, not completed/cancelled, and due ≤ tomorrow, or *high* due in 2–3 days, or *urgent* with no date | Overdue / due today / due tomorrow / urgent / high-priority approaching | 0 / 1 / 3 / 4 / 5 |
| Activity *reminder* component | date ≤ tomorrow and not done | Overdue / due today / due tomorrow reminder | 0 / 1 / 3 |
| To-do / checklist | open, assigned to me (or unassigned and mine or shared), target ≤ tomorrow, or *high* in 2–3 days | Overdue / due today / tomorrow / high-priority | 0 / 1 / 3 / 5 |
| Partner check-in request | sent to me, unanswered, not expired | Respond to a partner check-in | 2 |
| Activity mention / reply | unread notification of kind mention/reply on an Activity | Your partner mentioned you / Unread reply | 2 |

Personal snoozes hide an item until a chosen date, for the snoozing person only.

**Coming up together: sources.** Calendar events (yearly ones projected to this year), dated to-dos, planned Experiences, Trip start dates, Trip itinerary items, Occasions (annual projected), "Prepare:" and "Save for:" occasion lead dates, occasion preparation steps, Activity due dates, and Activity date/countdown components. Everything is filtered by the reader's permissions.

**Edge cases and gaps**
- [HIGH] First-class **Reminders** (Remember → Reminders) appear in neither section.
- [HIGH] **Recurring checklists** (no target date) never appear. The "morning leaving checklist" will not show up on the morning it is needed.
- [MED] Not included anywhere on Today: unread letters, days off, public holidays, trip documents, new experience suggestions.
- [LOW] A to-do branch checks `priority = 'urgent'`, but to-dos only allow low/normal/high, so that branch never fires (Activities do allow *urgent*). The two modules use different priority scales.
- [LOW] Meeting counter: if "last time we met" is today, it reads "Coming up" instead of "Today".
- [LOW] In *together* mode the last-met and next-meeting counters still show. That may be intentional, but the wording assumes distance.

## 5.3 Calendar

**How to use.** Remember → Calendar. Switch **Month / Week / Day**. Tap a day to see its entries. Add an event with title, details, date, optional start/end time with IANA zone, **for whom** (me, partner or both), Shared/Private, and **repeat yearly** (birthdays, anniversaries). From an event: edit, archive/restore, **email** it (opens the mail app), **remind my partner now** (once per event per day), share privately (view-only), and see history.

**Business rules**
- Calendar *shows*: events (own + shared), dated to-dos, **personal days off**, **Occasions**, and **public holidays** from the countries enabled in Settings (US, Egypt; Saudi civic days are date-only).
- A new **shared** event notifies the partner once ("New shared event"). Editing an event does not notify.
- `@Name` in title/details notifies the partner (shared events only).
- Yearly events on 29 Feb roll to 28 Feb in non-leap years.

**Edge cases and gaps**
- [MED] The Calendar does **not** show Reminders, Trips/itinerary, Activities with due dates, or planned Experiences, but Today's "Coming up" does. These are two different "truths" about the same week.
- [MED] **No pre-event alert.** Nothing pushes "Kandice's appointment in 1 hour". The only alert is a manual "remind partner now" or a separately created Reminder linked to the event.
- [LOW] The Week view is an agenda list, not a 7-column grid like Google/iPhone calendars.
- [LOW] No phone-calendar import or sync (still an open decision).

## 5.4 To-do and Checklists

**Concept.** Every item is a **checklist** (parent `tasks` row) with sub-items (`task_checklist_items`). Old standalone tasks were migrated under a legacy checklist.

**How to use.** Remember → To-do and Checklists → **Create checklist**: title, priority (low/normal/high), optional target date, visibility (Shared/Private, fixed after creation), assignee (me, partner, both), and **Repeat checklist**. Add sub-tasks inline, tick them, remove them, reorder. Filter icon at top: *All / Shared / Private*, status *Open / Completed / Cancelled / All*, and *Due today / overdue*. A speaker icon **reads the checklist aloud** (phone text-to-speech).

**Recurrence engine (strong)**

| Rule | Behaviour |
|---|---|
| none / daily / weekly / monthly / yearly | Classic cycles (weekly cycles start Monday). |
| weekdays · weekends · workdays (from each person's work days) | Schedules only on matching days. |
| selected weekdays · every N days · every N weeks · month days (incl. −1 = last day) | Advanced patterns. |
| Exclusions | Skip recorded days off; skip **US federal holidays** (observed); extra skip dates typed as YYYY-MM-DD. |
| Time zone | Each responsible partner's phone zone, or a typed IANA override. |
| Completion | Stored **per person, per cycle date**. Each partner has independent ticks; yesterday's state is kept as history; a new cycle starts fresh. |

**Business rules**
- Cancelling keeps the record (red strikethrough). Completing shows a strikethrough. There is no hard delete.
- Linked to Trips: a trip can generate a preparation checklist (`trip_id`).
- A Reminder can point at a checklist.

**Edge cases and gaps**
- [HIGH] Recurring checklists never surface on Today and produce no "time to do your morning checklist" alert.
- [MED] Holiday skipping is **US-only and hard-coded**. It ignores the Egypt/Saudi holiday sources selected in Settings.
- [MED] The time-zone override and extra skip dates are **typed as raw text** ("America/New_York", "2026-12-24, 2027-01-02"). This is too technical for normal users.
- [LOW] Shopping-specific fields (quantity/unit) from the retired Lists module do not exist on checklist items.

## 5.5 Reminders (first-class)

**How to use.** Remember → Reminders → **New reminder**: title (≤160), details, **date and time** (phone's current zone), audience **Only me / Partner / Both of us**, visibility, and an optional **related item** (a checklist, calendar entry or occasion). Quick picks: *Later today · 2 hours*, *Tomorrow · 9:00 AM*, or custom.

**Responding to a reminder (per recipient)**

| Action | Rule | Result |
|---|---|---|
| Mark job done | optional outcome note | State *done*, no further alerts |
| Needs follow-up | **note required** | State *follow-up*, re-alerts once after **24 hours** |
| Snooze until… | must be > 1 minute and ≤ 366 days ahead | Re-alerts at the chosen time |
| Reopen | none | Back to *pending*, alerts now |

Every response is written to `reminder_actions` (who, action, note, next alert) and is visible to both partners on a shared reminder.

**Automation.** Every 5 minutes the server writes a "Reminder: [title]" notification to each due recipient. The push job then delivers it within about 1 minute. Changing a reminder's date reschedules the recipients. `@Name` in a shared reminder notifies the partner.

**Special uses already built on Reminders.** Occasion preparation reminders (phase *save / research / order / prepare* for a specific annual instance) and private **"remind me to send a little love"** reminders.

**Edge cases and gaps**
- [HIGH] **No recurrence.** "Medication at 8 and 20 every day" or "Fill the gas every Friday" must be created again each time.
- [MED] **No quiet hours or days-off awareness.** Alerts fire at the stored instant even if that is the middle of the recipient's night.
- [MED] **Linked source is not re-checked.** A reminder still fires after its checklist is cancelled or its event archived.
- [LOW] Linking supports only checklist, calendar and occasion, not Activities, Trips, Notes or Contacts.
- [LOW] Two different "reminder" concepts exist: this module, and the Activity *reminder* component ("Phone alerts are not yet enabled"). Users will confuse them.

## 5.6 Notes 2.0

**How to use.** Remember → Notes. A library with search, pinned notes first, a filter/history icon at top and archived notes in History. Open a note in the **rich editor** (Quill): headings, bold/italic, bullet and numbered lists, **checkboxes**, links. Add **photos** to a note. **Link** a note to a checklist, calendar entry, occasion or experience, and see **backlinks** ("Related notes") from those records. Mention the partner with the **@ button**. Shared/Private; private notes can be shared view-only.

**Business rules.** Up to 30,000 characters. Edits are protected against stale overwrites (the "changed on another device" check). Every create/edit/archive is in the action history. A note is never auto-translated.

**Edge cases and gaps**
- [LOW] Links cannot point to Activities, Trips, Contacts or Memories.
- [LOW] Mention uses a separate button rather than inline "@" suggestions (Activity chat does it inline).

## 5.7 Occasions & surprises (gift planner)

**How to use.** Remember → Occasions & surprises → **Plan an occasion**: name, honoree, type (birthday, anniversary, holiday, celebration, other), date, repeat yearly, private (surprise) or shared, budget and currency, saving lead days and preparation lead days, notes. Inside a plan:
- **Preparation timeline:** suggested *Save* (default 60 days before), *Research* (30), *Order* (14), *Prepare* (3). Each can be turned into a dated private reminder at 9:00 for that year's instance.
- **Preparation steps:** your own to-do steps with due dates.
- **Budget workspace:** gift ideas with merchant, link, unit price, quantity, currency, expected arrival, product rating, **my preference score**, status (*wish → shortlisted → planned → purchased / cancelled*), order status (*not ordered → ordered → shipped → delivered → return requested → returned / cancelled*), order number, tracking link, return reason. Totals for planned, reserved, spent and wishlist, per currency, with "over budget by…".
- **Compare & save gift combinations:** tick items to see the running total, a warning when an item **arrives after the occasion**, and save the combination as a *proposal* (proposed → approved / superseded).
- **From Activity:** research options from a Coordinate Activity can be sent into the occasion budget.
- Change history for the plan, its steps and every budget change.

**Automation.** Creating a **shared** occasion notifies the partner. Occasions appear in the Calendar and in Coming up (with "Prepare:" and "Save for:" lead dates). `@Name` in title/notes notifies the partner.

**Edge cases and gaps**
- [MED] Your timing rule (second half of month → last week of previous month; first half → one month earlier) and **salary-month awareness are not implemented**. Fixed lead days are used instead.
- [LOW] Order tracking is manual (no retailer or carrier integration). Status does not advance automatically after the occasion date.
- [LOW] One-off past occasions stay in *planning* until changed by hand.

## 5.8 People & saved contacts

**How to use.** Remember → People & saved contacts. One library that merges **standalone contact cards** and **contacts captured inside Activities** (shown with "From: [Activity]", which opens the Activity). The (+) button or **Remember someone** opens the card editor: name, contact person, phone, email, address, website, company, role, working hours, notes, and Shared/Private. Cards are collapsible. Extra actions: **Import from phone** (native picker, preview, then save), **Save to phone** (opens the native Add Contact form pre-filled), and **receive a vCard** shared from the phone's Contacts app (Android). There is a duplicate warning on matching phone or email ("Save separately" if intended), soft delete with a "Recently deleted" history and restore, and an edit history.

**Edge cases and gaps**
- [HIGH] **Not in global search.** "Who is X again?" can only be answered inside this screen.
- [LOW] Deleted cards get a 30-day `purge_eligible_at` date, but **no job ever purges them**. The "retention period" is cosmetic.
- [LOW] There is no emergency/Medical ID link (platform feature, not implemented).

## 5.9 Coordinate: Activities (the core workspace)

**Concept.** An **Activity** is a purpose-centred workspace ("Find a heater", "Choose a gym class for the baby"). It needs only a **title** and optional details. Optional fields are visibility, priority (low/normal/high/urgent) and due date.

**Components you can attach (15 types).** Link, note, **option** (product or provider with price, specifications and source), step, date, price observation, specification, reminder, tag (from a shared **tag inventory**), mention, map location, **photo/screenshot** (private bucket), **contact** card, **voice note**, **countdown**. Components can be nested (an option with its own price and spec children).

**Working together**
- **Compare options:** a matrix of prices, specifications and links across options.
- **Like / dislike** per option, per partner, independently.
- **Conversation:** chat with replies, references to a specific component ("Discussing: …"), inline **@partner suggestions while typing**, copy, and **voice messages** recorded in the composer.
- **Decision & outcome:** *Choose this option* (stage → decided), *Purchased*, *Delivered* (→ completed), *Registered* (→ completed), *Postponed* (→ on hold), *Reopened* (→ exploring), *Cancelled*. Each is recorded atomically with an optional reason and purchase/registration/delivery details.
- **Stages:** exploring → comparing → decided → purchased / registered → completed. On hold and cancelled are side exits.
- **Lifecycle:** edit (original title/body preserved), archive / restore, remove component (kept in history) / restore. There is an Activity edit history, component history and outcome history.
- **Send to occasion plan:** pushes an option into an Occasion budget.
- **Share-in:** from another Android app, "Save to OneSpace" creates a new Activity, attaches the link as an option (with price and specifications) to an existing Activity, or saves it as a Shared Experience.

**Automation and alerts**
- @mention in chat → "Your partner mentioned you" notification and push.
- Reply to the partner's message → "Your partner replied".
- Due dates, urgent/high priority and reminder components → Needs attention.
- Date and countdown components → Coming up and Countdowns.

**Edge cases and gaps**
- [HIGH] **A normal chat message (not a reply, no @mention) sends no notification.** The heater example from your brief ("hey, don't forget to look at this") would be missed.
- [MED] Private Activities generate no notifications at all, by design. Make sure users understand that "Private to me" is a personal research space.
- [LOW] Reminder components show only in Today ("Phone alerts are not yet enabled").
- [LOW] Prices are snapshots; nothing re-checks the store.

## 5.10 Letters

Write a letter, keep it as a **private draft**, or **send** it (permanent, shared). Received letters can be answered with a **reply**. "Read by your partner" or "Sent · not marked read yet" shows status. Sending notifies the partner. A draft that changed on another device is protected from overwrite.

**Gaps.** [LOW] Unread letters do not appear in Needs attention. There is no scheduled send ("deliver when she wakes up"), which was in your original brief.

## 5.11 A little love (gestures, self-reminders, rituals)

**Sending.** Tap a gesture type: Hug, Thinking of you, You made me smile, Good morning, Sweet dreams, Proud of you, You have got this, Thank you, Lucky to have you, I miss you, I miss us together, I miss our home, I miss our kids, I miss our furry ones (14 types). The app picks a **random message from that type's pool**: built-in messages (editable or hideable per sender) plus your own custom gestures of that type. The partner gets a notification with a type-specific icon. Opening it shows a themed pop-up. Sent and Received history sits behind a header icon.

**Managing (Settings → My love gestures).** Expandable cards per type with message counts, an edit button for every message, "Hide from random pool", and **Create my own gesture** (name, type, message, optional ritual moment).

**Self-reminders ("Remind me to send a little love").** These create a **private Reminder** to *you* (never an automatic send) for **morning 9:00, after work 18:00 or evening 21:00** (phone time), for any type or a specific one. The card shows "Last sent N hours/days ago".

**Automatic rituals (legacy, consent-based).** The sender enables morning / after-work / goodnight. The recipient must turn on "Allow scheduled gestures from my partner" and set a full sleep window and time zone. The server sends 15 min after wake, 15 min after work end (work days only, not on days off), or 20 min before sleep; never inside the sleep window; once per day per ritual.

**Edge cases and gaps**
- [MED] The roadmap asked for **smart self-reminders**: aware of when the last gesture was sent, working days, holidays, days off and low mood (≤3, if shared). Today they are fixed clock times that ignore the work schedule already stored in Profile.
- [MED] Rituals are effectively dormant (no schedules enabled, and no sleep window set on either profile), yet the settings remain. A product decision is pending: retire them or keep them as an explicit opt-in.
- [LOW] Ritual logic quirk: if the sender has *any* scheduled custom gesture of a different type for that moment, it always replaces the random pool choice.

## 5.12 Daily check-ins

**Two primary actions**
1. **Record my feeling:** mood (rating), *What's on my mind*, *Something I'm grateful for*, Shared or Private. One entry per person per day (editable). Sharing notifies the partner ("Your partner shared how they feel today").
2. **Check on my partner:** sends an invitation with an optional message. The partner answers with mood, *What's on your mind?* and *Something you need to talk about?*. The sender is notified of the answer and can **acknowledge** it (heart, thank you, hug).

**Rules.** Invitations stay open **7 days**, then quietly expire. Expired requests leave Needs attention. A private feeling never reaches the partner, a notification or search. There are history and filters at the top, plus search across messages and gratitude.

**Gaps.** [LOW] No suggestion engine ("you haven't checked in for 3 days"), which was intentionally deferred.

## 5.13 Shared experiences & games

A single library for **Movies, Shows, Music, Books, Games, Other**. Each item has a title, description, platform, link (Watch / Play / Open button), status (*suggested → planned → enjoyed*) and optional planned/enjoyed dates. Each partner independently marks interest; **"Mutual pick"** appears only when both are interested. Mark watched/enjoyed and **rate** directly from the card, write reviews, and **comment** (R45: authors can edit, retract and restore their own comments; not yet in an APK). Filters and archived history are at the top. A new suggestion notifies the partner. Games are simply a category with an external invitation link.

**Gaps.** [MED] No posters, genres or metadata, and no genre filter. [LOW] Planned/enjoyed dates remain even though you asked to drop them (they feed the agenda).

## 5.14 Memories, daily selfie and Scrapbook Studio

- **Memories:** a journal entry, photo memory or **daily selfie** (camera or gallery). Shared or private, pinned, archived/restored, with four photo layouts (grid, collage, one-large-others-below, overlapping stack).
- **Photo library:** captions plus **people tags, place tag and custom tags**, searchable. Photo edit history.
- **Scrapbook Studio:** choose one of **4 designed templates** (Polaroid letters, Our adventures, Little moments, Milestone story), fill photo and text slots, change design without losing content, **invite the partner** to co-create (accept/decline), and **export a page as PNG** (Android).

**Gaps.** [LOW] Only 4 templates. There are no stickers or handwriting fonts, no automatic collage, and no iOS export. The Connect hub still says "Daily selfies … are planned" even though they exist.

## 5.15 Shared goals

Goals with title, description, target date, progress %, status (active / paused / achieved) and visibility. They are listed in Connect and counted on Today.

> **Note.** You said you never requested Shared Goals and asked what they meant. The module remains in the app. Decide whether to keep, repurpose (for example "savings goal for the next visit") or hide it.

## 5.16 Trips & journeys

**How to use.** World → Trips → new trip: title, origin, destination, dates (or *flexible*), status (*planning → booked → traveling → completed / cancelled*), Shared/Private, notes. Inside a trip:
- **Itinerary:** flight, stay, transport, activity, booking and note items with local date/time, end date/time, provider, booking reference (copy button), link, estimated cost and currency, and a done tick.
- **Flight research & comparison:** options with route, dates, stops, baggage/seat details, price, currency, link (Google Flights or airline) and status (*considering → proposed → booked / rejected*). A booked option can be **added to the itinerary**.
- **Travel documents:** boarding passes, itineraries, tickets, receipts, photos and other PDF/JPEG/PNG/WEBP files up to 10 MB in a private bucket. They can be attached to an itinerary item and open via 90-second signed links. A partner is notified when a document is shared.
- **Preparation:** one tap creates a linked **trip checklist** from a template (e.g. leaving home, travel day).
- **Conversation** with change history. The partner is notified of new shared trips and messages.

**Gaps**
- [HIGH] **No offline access** to documents. With no connection the screen shows "Documents unavailable. Check your connection", which fails at exactly the moment a boarding pass is needed.
- [MED] **No trip reminders** (check-in opens, leave for the airport, "safe flight" wishes) and no automatic status change by date.
- [LOW] No visit history timeline (past trips are not used to update "last time we met").

## 5.17 Notifications and push

**In-app.** The bell shows unread items. The list filters All/Unread, supports mark-all-read, shows a type-specific icon and subtitle, and opens the matching screen (Activity, Calendar event, Reminder, To-do, Note, Occasion, Trip, Experience, Letters, Check-in, gesture pop-up, Scrapbook).

**Push.** When a notification row is created (or rescheduled), one push per enabled device of the recipient is queued in a private outbox. Every minute the worker sends up to 25. Failures retry, and dead tokens are retired. Android permission is requested once.

**Gaps**
- [HIGH] The push text is always **"OneSpace — You have a new update in your shared space."** This preserves privacy but never says *what* happened. It is not localised and has no type-specific title or icon.
- [HIGH] Tapping a push opens the **notification list**, not the item or gesture pop-up.
- [MED] There are no quiet hours, priority levels or per-type mute settings.

## 5.18 Search, mentions, history and share-in

- **Global search** (⋮ → Search our space): searches Activities, Activity components, calendar events, to-dos, notes, letters, trips, itinerary items, travel documents, experiences, occasions, reminders, goals and memories. Minimum 2 characters, up to 12 results per section. Access is filtered by RLS.
- **Not searched:** [HIGH] saved contacts, checklist sub-items, Activity chat, Experience comments, check-ins, photo tags (searchable only inside Memories) and tag inventory.
- **Mentions** notify on: notes, to-dos, calendar events, occasions, experiences, reminders (shared only) and Activity chat. Matching is on **"@" + the partner's full display name** (Activity chat also accepts the first name). Nicknames from "Preferred names" are not recognised.
- **History** icons at the top exist on most collection screens. To-dos, check-ins, letters and gestures use their own patterns.

## 5.19 Settings, profile, themes and language

- **Settings (⋮ → Settings):** Personalization (preferred names for partner, several labels used at random), Our relationship (Living apart / Together, last met, next meeting), Weather city, temperature unit (°F/°C), Regional holidays (US/Egypt/Saudi), Birthdays & special dates (→ Occasions), Working hours & sleep, Days off & sleep exceptions, My love gestures, Thoughtful rituals, Appearance.
- **Profile:** display name, password, time zone (automatic from phone), weather city, daily schedule (work start/end, work days, sleep), consent to scheduled gestures, performance timings.
- **Appearance:** palettes Coastal Blue, Rose & Plum, Sage & Sand, Midnight Indigo; Light / Dark / Follow phone; seasonal accents that respect reduced-motion; a private occasion can tint *your* phone's theme.
- **Language:** English or Arabic (RTL) per person. User content is never translated.

**Gaps.** [MED] Weather city and work schedule can be edited in both Settings and Profile (duplicated entry points). [MED] About three-quarters of on-screen text is hard-coded English, so the Arabic experience is mixed-language.


# 6. Use cases and end-to-end user journeys

## UC-1 "Find a heater": shopping research to purchase (Coordinate)

1. Kandice creates Activity **"Heater for the bedroom"** with details (Shared, priority normal).
2. Ahmed shares an Amazon link from the Amazon app → **Save to OneSpace → Compare this option** (price $79, spec "Timer: yes").
3. Ahmed adds a Walmart option and a **screenshot** component.
4. Ahmed writes "Don't forget to look at this". → **Kandice receives nothing** unless he types `@Kandice …` or replies to one of her messages. (Gap, §5.9.)
5. Kandice opens the **comparison matrix**, **dislikes** both, and adds a note "needs timer and auto shut-off".
6. Kandice adds her own option and asks `@Ahmed what about the voltage?` → Ahmed is notified (mention).
7. Ahmed **likes** it. Kandice taps **Choose this option** → stage *decided*. Then **Purchased** with order details → stage *purchased*. Later **Delivered** → *completed*.
8. Every step is in Outcome history and Activity history. The Activity moves to *Finished*.

## UC-2 "Gym class for the baby": research with steps and contacts

Create the Activity, then add three **contact** components (gym A/B/C, working hours), a **step** "Email the three places" (mark completed when done), **notes** "Reply from A", a **date** component "In-person visit", then **Registered** → *completed*. The gyms' contacts appear in **People & saved contacts** with "From: Gym class" origin.

## UC-3 Birthday planning with a budget

1. Occasion **"Kandice's birthday"**, private, yearly, budget $300, lead days 60/30.
2. Turn the *Save* and *Research* suggestions into reminders (9:00 a.m. on the suggested dates).
3. Collect 8 gift ideas with links, prices, arrival dates and preference scores. Mark some *shortlisted*.
4. **Compare & save combinations:** select 3 → total $265, one item flagged "Arrives after occasion" → swap it → save as **proposal**.
5. Mark items *purchased*, enter order numbers and tracking links, update order status manually, record a **return** with reason, then reopen the comparison to find an alternative.
6. After the day, set status **Celebrated**. (Not automatic.)

## UC-4 Morning leaving checklist (recurring, read aloud)

Create checklist **"Leaving for work"**, Shared, assigned to Kandice, repeat **workdays**, skip days off. Each morning a fresh cycle starts in her time zone; she can tap the speaker to **hear it read aloud**. Her ticks do not affect Ahmed's. **Gap:** nothing reminds her that morning and it does not appear on Today. A voice command ("Hey OneSpace, read my morning checklist") does not exist.

## UC-5 Remind my partner across time zones

Ahmed creates a **Reminder** "Doctor appointment 3 pm", audience **Partner**, linked to the calendar event. It is stored as an absolute instant. The server alerts Kandice at the correct moment in her zone. She chooses **Done** with a note, or **Needs follow-up** (note required → alerts again tomorrow). Ahmed sees her outcome. **Gap:** if he picks a time during her sleep, it will buzz anyway.

## UC-6 Checking on each other

Ahmed taps **Check on my partner** → Kandice gets a notification and a Needs-attention item → she answers (mood, on her mind, something to talk about) within 7 days → Ahmed is notified and **acknowledges with a hug**.

## UC-7 Planning a reunion trip

Create a Trip with flexible dates → save 3 flight options from Google Flights → **propose** one → mark **booked** → **add to itinerary** → upload boarding pass PDF → generate the **travel-day checklist** → discuss in trip conversation. **Gaps:** no offline boarding pass, no "check-in opens" reminder, and the trip end does not update "last time we met".


# 7. Automated system actions and alert triggers (complete catalogue)

## 7.1 Database triggers that create notifications

| # | Trigger (table → function) | Fires when | Recipient | Notification kind | Push |
|---|---|---|---|---|---|
| 1 | activity_comments → notify_activity_comment | new comment in a **shared** Activity containing `@FullName` or `@FirstName`, or replying to the partner's comment | partner | mention / reply | yes |
| 2 | calendar_partner_reminders → notify_calendar_partner_reminder | "Remind partner" on an event (max once per event per day) | partner | reminder (calendar) | yes |
| 3 | space_events → notify_new_shared_event | a **shared** event is created | partner | event | yes |
| 4 | space_events / tasks / occasion_plans / shared_experiences → notify_shared_module_mention | create or title/text edit containing `@FullName` on a shared record | partner | mention | yes |
| 5 | notes → notify_shared_note_mention | shared note mentions partner | partner | mention | yes |
| 6 | reminders → notify_shared_reminder_mention | shared reminder mentions partner | partner | mention | yes |
| 7 | couple_letters → notify_sent_letter | a letter changes to *sent* | partner | letter | yes |
| 8 | partner_gestures → notify_partner_gesture | gesture sent (manual or automatic) | recipient | gesture | yes |
| 9 | partner_checkin_requests → notify_partner_checkin_requests | request created / answered | recipient / sender | checkin_request / checkin_response | yes |
| 10 | daily_checkins → notify_shared_daily_checkin | a **shared** feeling is recorded | partner | checkin_shared | yes |
| 11 | shared_experiences → experience_suggestion_notice | new experience | partner | experience_suggestion | yes |
| 12 | shared_experience_comments → experience_comment_notice | new comment | partner | experience_comment | yes |
| 13 | shared_trips → notify_trip_created | **shared** trip created | partner | trip_suggestion | yes |
| 14 | trip_messages → notify_trip_message | new trip message | partner | trip_message | yes |
| 15 | trip_attachments → notify_trip_document | document uploaded | partner | trip_document | yes |
| 16 | occasion_plans → notify_shared_occasion | **shared** occasion created | partner | occasion_shared | yes |
| 17 | scrapbook invite RPC | partner invited | partner | scrapbook_invite | yes |
| 18 | space_notifications → queue_notification_push | any notification inserted or re-timed (or marked unread again) | each enabled device | (outbox) | n/a |

## 7.2 Scheduled automations

| Automation | Rule |
|---|---|
| Due reminders | Every 5 min; recipients in *pending* or *follow-up* whose alert time passed and who were not already notified for that time; still space members; reminder not archived. Up to 100 per run. |
| Follow-up re-alert | Choosing *Needs follow-up* schedules one more alert 24 h later. |
| Automatic gestures | Every 5 min; see §5.11. The 10-minute send window and the 5-minute cadence guarantee at most one send per ritual per day. |
| Push delivery | Every 1 min; 25 per batch; retry on network/FCM errors; retire on UNREGISTERED. |

## 7.3 Other system-generated actions

- **Audit capture:** every insert/update on notes, to-dos, goals, memories, events, reminders, occasions, experiences (plus trips, contacts, check-ins, check-in requests and Experience comments) writes a metadata row (created / edited / archived / restored / cancelled / reopened + changed field names).
- **Revision tables:** activities, components, occasion plans and steps, budget items, trips/items/messages, contacts, memory photos and experiences store before/after content for their own history screens.
- **Recipient fan-out:** creating a Reminder auto-creates recipient rows (me / partner / both). Creating one for "partner" fails if no partner is connected.
- **Guards:** event "for whom" must be a member; checklist ticks must belong to the parent checklist; trip checklists must reference a visible trip; occasion budget links must reference a visible Activity option; scrapbook pages may only reference permitted photos; letters cannot be edited after sending.
- **Expiry:** check-in requests expire after 7 days (computed at read time, no job).
- **Timestamps:** updated-at clocks, letter send time, check-in reply time.

## 7.4 What does NOT happen automatically (expectations to manage)

No alert before calendar events, trips, Activity due dates or occasion dates (unless you create a Reminder). No recurring reminders. No quiet hours for anything except automatic gestures. No push when a trip, event, occasion, to-do or note is *edited*. No notification for plain Activity chat. No automatic status changes (trip → traveling/completed, occasion → celebrated, order → delivered). No purge of soft-deleted contacts. No alert when a recurring checklist cycle starts.


# 8. Configuration dependency tree

```
OneSpace (Android preview com.onespace.onespace.preview)
├── Flutter app (lib/)
│   ├── Supabase URL + publishable key (hard-coded in main.dart)  → Supabase project ugwrpeduzyzrujkizqfo
│   ├── SecureAuthStorage (Android keystore)  → one persisted session
│   ├── local_auth  → phone biometric / PIN enrolled  (else password only)
│   ├── Firebase.initializeApp()  ← android/app/google-services.json
│   │      └── injected at CI build from GitHub secret ONESPACE_GOOGLE_SERVICES_JSON_BASE64
│   │          (package must equal com.onespace.onespace.preview, else build fails)
│   ├── FCM token  → rpc register_push_device → public.push_devices
│   ├── Open-Meteo (no key)  → weather city + forecast  → profiles.weather_*
│   ├── Nager.Date v4 (no key)  → space_holiday_sources (US / EG)  + Saudi hard-coded days
│   └── Android method channels: incoming_share, contacts bridge, checklist TTS
├── Supabase
│   ├── Auth (email/password; redirect URL for confirm/reset → docs/AUTH_CALLBACK_SETUP.md)
│   ├── Postgres: 66 public tables (+ private.push_outbox), RLS on all
│   │   └── private schema helpers (is_space_member, has_object_view_grant, …)
│   ├── Storage buckets (private): activity-media, activity-voice, trip-documents,
│   │   memory-photos, note-images  (RLS on storage.objects by path → parent record)
│   ├── pg_cron
│   │   ├── onespace-due-reminders (5 min)  → space_notifications
│   │   ├── onespace-consented-gestures (5 min)  → partner_gestures → space_notifications
│   │   └── onespace-fcm-push-delivery (1 min)  → pg_net POST → Edge Function
│   │         └── header x-onespace-push-secret = Vault secret "onespace_push_worker_secret"
│   ├── Edge Function onespace-push-delivery (verify_jwt = false, secret-gated)
│   │   ├── env ONESPACE_PUSH_CRON_SECRET          (must equal the Vault secret)
│   │   ├── env ONESPACE_FIREBASE_SERVICE_ACCOUNT_JSON  → Google OAuth → FCM HTTP v1
│   │   └── env SUPABASE_SERVICE_ROLE_KEY  → rpc claim_push_outbox / complete_push_delivery
│   └── Realtime (streams for lists, chat, notifications)
├── Firebase project  → Cloud Messaging only (Android app registered for the preview package)
└── GitHub
    ├── Workflow "Verify OneSpace iteration": analyze + tests on push to main
    ├── Workflow "Build and publish OneSpace APK": only on explicit release marker
    │   └── dev signing key in tools/dev-signing (NOT for production)
    └── Releases: preview-0.1.xxx APKs
```

**Single points of failure and coupling**
- [MED] The push chain has **five links that must match**: Vault secret ↔ Edge env secret ↔ Firebase service account ↔ the device's `google-services.json` ↔ an enabled device row. If any one breaks, pushes fail silently. In-app notifications still work, but nothing alerts you that push is down.
- [MED] **Migration history drift:** R30–R44 schema (0095–0105) is live but missing from `supabase_migrations`. Re-applying the history to a new project or branch would produce a database without check-in expiry, acknowledgements, occasion phase reminders, love-gesture reminders, note references or the action history.
- [LOW] Supabase URL and key are compiled into the app; switching projects (e.g. a region move) needs a new APK.
- [LOW] The development signing key is in the repository. That is acceptable for previews only.


# 9. Open loops and broken cycles

An *open loop* is a process that starts but never finishes, or that finishes without informing the person who needs to know. A *broken cycle* is a repeating process that does not repeat or does not reset correctly.

| # | Sev | Loop / cycle | What happens in code | Effect |
|---|---|---|---|---|
| L1 | [HIGH] | Reminder → repeat | No recurrence column; after *done* the reminder is finished forever | Routine items (meds, laundry, gas) cannot be automated |
| L2 | [HIGH] | Activity message → partner awareness | Only mentions and replies notify | Requests made in chat silently drop: the exact problem OneSpace was built to solve |
| L3 | [HIGH] | Recurring checklist → user | New cycle starts with no alert and no Today entry | Routines rely on memory |
| L4 | [HIGH] | Push → item | Push opens the notification list; body is generic | Extra taps; gesture pop-up not shown from push |
| L5 | [MED] | Reminder → linked source | Dispatch does not check if the source checklist/event/occasion was cancelled or archived | Alerts for things already cancelled |
| L6 | [MED] | Reminder → sleep/days off | Dispatch ignores profile sleep window | Night-time alerts across time zones |
| L7 | [MED] | Needs follow-up | Re-alerts once after 24 h, then waits silently in *follow-up* | Follow-ups can be forgotten after one nudge |
| L8 | [MED] | Trip lifecycle | Status never advances by date; trip end does not update "last time we met"; no reminders | Counters and statuses go stale |
| L9 | [MED] | Occasion lifecycle | Status never advances; one-off past occasions stay "planning"; orders never auto-advance | Stale planning lists |
| L10 | [MED] | Calendar ↔ Today | Two different source lists | "Is it on our calendar?" depends on where you look |
| L11 | [LOW] | Contact soft delete | `purge_eligible_at` set to +30 days, nothing purges | Retention promise not kept |
| L12 | [LOW] | Activity reminder component | Shows in Today only; "Mark handled" is the only exit | Duplicate reminder concept |
| L13 | [LOW] | Love self-reminders | Fixed 9/18/21 h, independent of last gesture or schedule | Feels mechanical; can fire on days off |
| L14 | [LOW] | Edited shared records | Edits to events/trips/occasions/notes don't notify (only mentions) | Partner unaware of a changed appointment time |
| L15 | [LOW] | Goals | Created, counted, never connected to anything | Orphan module |
| L16 | [LOW] | Relationship mode | DB has 4 modes; UI writes only 2 | Same-time-zone apart couples show two identical clocks |
| L17 | [LOW] | Push health | No alert or diagnostics when the outbox stops sending | Silent failure |


# 10. Inconsistencies in behaviour

| Area | Inconsistency |
|---|---|
| Priority scales | Activities: low/normal/high/**urgent**. To-dos: low/normal/high. Attention logic tests *urgent* for to-dos, which can never match. |
| "Reminder" | Three meanings: first-class Reminders, Activity reminder components, and calendar "remind partner now". Different alerts, different screens. |
| Mentions | Inline "@" suggestions in Activity chat; a separate "Mention partner" button elsewhere. Chat accepts the first name; other modules require the full display name. Private records never notify (correct, but invisible to the user). |
| Top-of-screen actions | Standard History/Filter bar on 9 screens; To-do, Calendar, Check-ins, Letters and Gestures use other patterns. |
| History | Metadata-only history for most records; full before/after revisions for Activities, Trips, Occasions, Contacts, Experiences. History screens differ per module. |
| Concurrency | Stale-edit protection in Notes, Activities, Experiences, Memories, Scrapbook. Not in To-dos, Calendar, Reminders, Trips, Occasions. Last write wins there. |
| Holidays | Calendar honours US/Egypt/Saudi sources; checklist skipping knows only US federal days. |
| Time | Reminders stored as absolute instants; checklists as local days in a responsible person's zone; events as date plus optional zoned time; love/occasion reminders fixed at 9:00/18:00/21:00 device time. |
| Settings | Weather city and schedule editable in two places (Settings and Profile). Language is in both the ⋮ menu and Profile. |
| Brand text | "One Life, Two Places" vs "One Life. Two Places. One Space." |
| Stale copy | Connect hub: "Daily selfies and connected-app library imports are planned." (selfies exist). World hub: "More of our wider world will appear here." |
| Explore grid | 9 tiles; omits Reminders, Occasions, Contacts, Trips; includes Letters/Check-ins that also live in Connect. |
| Language | Approx. 288 translated vs 862 hard-coded strings; push and many notification texts English-only. |


# 11. UI / UX review and recommended enhancements

## 11.1 Principles to adopt app-wide

1. **One place for each truth.** One calendar, one Today feed and one reminder concept. Everything dated should flow into all three.
2. **Every alert lands on its object.** Push → exact item (or the gesture pop-up), never a list.
3. **Plain language over configuration.** Replace typed time zones and typed dates with pickers. Hide developer panels.
4. **Same frame on every screen:** title · search · filter · history at top; the primary action as a single floating button; the same card anatomy (title, owner/for-whom chip, status chip, privacy icon, date).

## 11.2 Screen-level recommendations

| Screen | Recommendation | Effort |
|---|---|---|
| Today | Add Reminders and today's recurring checklists to Needs attention; add "Unread letter" and "New suggestion" rows; make the Explore grid 8 or 12 tiles including Reminders, Occasions, People, Trips | M |
| Today | "Last met" = today → "Together today"; in Together mode rename counters to "Date night / next outing" or hide | S |
| Relationship | Three-choice selector: Together · Apart (same time zone) · Long distance; map to existing DB modes | S |
| Calendar | Add Reminders, trips, Activity due dates and planned experiences as coloured layers with toggle chips; true 7-column week grid; pre-event alert option on each event | M–L |
| To-do | Time-zone picker (searchable list) and date chips instead of typed text; "today's routines" view; holiday skipping uses selected holiday sources | S–M |
| Reminders | Repeat (daily, weekdays, every N, specific days, monthly); "respect recipient's sleep" toggle (default on); show the recipient's local time when choosing a time for the partner | M |
| Coordinate | Notify the partner on every new chat message (batched per Activity, at most one push per 10 min); "Needs your input" badge | S |
| Notifications | Type-specific, localised push title and body (privacy-safe, e.g. "New letter from Kandice"); deep link to object; per-type mute and quiet hours | M |
| Search | Add contacts, checklist items, chat, comments, photo tags, tags; group results; recent searches | M |
| Mentions | One shared inline @-autocomplete widget everywhere; server matching on first name and preferred labels | M |
| Trips | "Save offline" for documents (encrypted local cache), a boarding-pass quick view on Today on travel day, and check-in / leave-for-airport reminders | M–L |
| Experiences | Poster/cover by link preview (Open Graph image) and genre field with filter | M |
| Settings | Single home for all preferences; Profile only for identity and password; remove the performance panel from Profile (move to a hidden developer menu) | S |
| Language | Complete Arabic catalogue; localise notification and push text by the recipient's language | M |
| Accessibility | Manual contrast pass on seasonal overlays and dark mode; test at 130% font scale; keyboard-safe composer in all editors | S–M |


# 12. Security, data and engineering review

**Strengths.** RLS on every table, private schema for privileged logic, security-definer functions with an empty search path, no service key in the app, private buckets with path-scoped policies, a server-side push worker gated by a secret, a metadata-only audit trail (no private content copied), 28 SQL regression test files and 244 Dart tests in CI.

| # | Sev | Finding | Recommendation |
|---|---|---|---|
| S1 | [MED] | Migration history drift (0095–0105 not recorded) | Register them as migrations (no SQL change), then enforce "every DB change = one migration file + record". |
| S2 | [MED] | Leaked-password protection off | Enable in Supabase Auth settings (zero code). |
| S3 | [LOW] | 9 SECURITY DEFINER RPCs callable by signed-in users (flagged by advisor) | Each is intentional and checks membership. Document the justification, or convert simple ones to SECURITY INVOKER. |
| S4 | [LOW] | `private.push_outbox` RLS enabled with no policy (INFO) | Correct (service-only). Add a comment so future audits don't "fix" it. |
| S5 | [MED] | No account deletion / data export | Required before any public release (store policy and privacy law). |
| S6 | [LOW] | 29 silent `catch(_){}` blocks in the app | Log to a local diagnostics buffer so field failures can be reported. |
| S7 | [LOW] | Region Seoul for users in Riyadh / Pennsylvania | Measure first (the performance panel exists). Move only with a planned migration and a new APK. |
| S8 | [LOW] | iOS not configured (no Firebase plist, no share extension) | Treat iOS as its own phase. |


# 13. Business and operational recommendations

## 13.1 Product strategy: depth over breadth

OneSpace already covers more ground than most commercial couple apps (Paired, Between, Lasting, Cupla, Honeydue). Its differentiator is not any single module. It is **follow-through**: a request, a date or an idea is captured once and reliably reaches the partner at the right moment, in the right language and time zone. Measure every next iteration against one question: *"Did this make something less likely to be forgotten or dropped?"*

## 13.2 Operating model for the two of you (pilot phase)

- **Weekly 15-minute review (Sunday):** open Coming up and Needs attention together; close or snooze stale items; check the Occasions planner for anything inside 60 days.
- **Golden rule for requests:** anything you ask for goes into an Activity (research) or a Reminder (action), never only into WhatsApp.
- **One owner per item:** use "for whom" and the assignee consistently; shared + assigned is better than shared + unassigned.
- **Track three pilot metrics manually for 4 weeks:** (1) requests dropped (target 0), (2) reminders answered within 24 h (target > 80%), (3) days with at least one gesture or check-in (target > 5/7).

## 13.3 If OneSpace becomes a public product (feasibility view)

| Topic | Assessment |
|---|---|
| Market | Crowded at the "cute couple app" end; thinner at the "shared life operating system" end, which is where OneSpace sits. Long-distance and cross-cultural couples (expats, multilingual) are a sharp, under-served niche. |
| Monetisation | Freemium: core free; **Plus** (~$4–6/month per couple) for unlimited storage, offline travel documents, scrapbook export packs, smart reminders and AI summaries. Gift planner affiliate links are possible but conflict with trust if used carelessly. |
| Prerequisites | iOS, account deletion and export, a privacy policy, complete localisation, production signing, store listings, support process, and moving off a single hard-coded project. |
| Main risks | Scope sprawl (19 modules) makes onboarding heavy, and sensitive data (moods, private notes, documents) raises the trust bar. Engagement depends on both partners adopting the app. |
| Recommendation | Keep it private for at least 2–3 months of real use, then decide based on the pilot metrics. If you go public, launch with 6–8 polished modules, not 19. |


# 14. Roadmap derived from the code

## Now (next 2 iterations): close the loops

1. Recurring Reminders, with quiet hours and the recipient's local time shown.
2. Notify on every Activity chat message (with batching).
3. Reminders and today's routines in Today. Calendar shows all dated sources.
4. Push: type-specific, localised text and deep links to the exact object or gesture pop-up.
5. Contacts, checklist items and chat in global search.
6. Repair migration history; enable leaked-password protection.
7. A single two-phone acceptance run of R45 (one APK), then freeze as the baseline.

## Next (iterations 3–6): make it dependable and pleasant

Offline travel documents and travel-day reminders · smart love self-reminders (schedule, last-sent, holidays, shared mood ≤3) · your occasion timing rule + salary month · three-option relationship mode · pickers instead of typed time zones and dates · unified @-autocomplete · complete Arabic · settings consolidation · decide on Goals and automatic rituals.

## Later: expand

iOS build · posters and genres for experiences · scrapbook template pack · AI level 2 (summarise an Activity, extract details from a document, suggest comparison criteria) · voice read-back via assistant shortcuts · phone-calendar import · retailer/carrier tracking · server region review · account deletion/export ahead of any public release.


# Appendix A: Database inventory (public schema)

| Domain | Tables |
|---|---|
| Identity & pairing | profiles, spaces, space_members, space_invitations, object_shares, push_devices |
| Today & attention | user_attention_snoozes, activity_attention_snoozes, space_notifications, record_action_history, space_tags |
| Calendar | space_events, calendar_partner_reminders, space_holiday_sources, personal_days_off |
| To-do | tasks, task_checklist_items, task_checklist_checks |
| Reminders | reminders, reminder_recipients, reminder_actions |
| Notes | notes, note_images, note_references |
| Occasions | occasion_plans, occasion_plan_steps, occasion_plan_revisions, occasion_budget_items, occasion_budget_log, occasion_proposals, occasion_proposal_items |
| Coordinate | activities, activity_components, activity_comments, activity_component_reactions, activity_decisions, activity_revisions, activity_component_revisions |
| Contacts | saved_contacts, saved_contact_revisions |
| Connect | couple_letters, couple_letter_reads, partner_gestures, gesture_templates, gesture_message_overrides, gesture_schedules, daily_checkins, partner_checkin_requests, partner_checkin_acknowledgements, goals |
| Experiences | shared_experiences, shared_experience_interests, shared_experience_reviews, shared_experience_comments, shared_experience_revisions |
| Memories | memories, memory_photos, memory_photo_revisions, scrapbook_pages, scrapbook_invites |
| Trips | shared_trips, trip_items, trip_flight_options, trip_attachments, trip_messages, trip_revisions |
| Private | private.push_outbox |

# Appendix B: Status enumerations (source of truth for workflows)

| Object | Allowed values |
|---|---|
| Relationship mode | not_set, living_together, apart_same_tz, apart_different_tz |
| Activity stage | exploring, comparing, decided, purchased, registered, completed, on_hold, cancelled |
| Activity priority | low, normal, high, urgent |
| To-do status / priority | open, completed, cancelled / low, normal, high |
| Reminder audience / recipient state | me, partner, both / pending, follow_up, done |
| Occasion status / kind | planning, preparing, ready, celebrated, cancelled / birthday, anniversary, holiday, celebration, other |
| Gift item status / order status | wish, shortlisted, planned, purchased, cancelled / not_ordered, ordered, shipped, delivered, return_requested, returned, cancelled |
| Gift proposal | proposed, approved, superseded |
| Trip status / item kind | planning, booked, traveling, completed, cancelled / flight, stay, transport, activity, booking, note |
| Flight option | considering, proposed, booked, rejected |
| Travel document kind | boarding_pass, itinerary, ticket, receipt, photo, other |
| Experience category / status | movie, show, music, book, game, other / suggested, planned, enjoyed |
| Goal status | active, paused, achieved |
| Letter status | draft, sent |
| Check-in acknowledgement | heart, thank_you, hug |
| Scrapbook invite | pending, accepted, declined |
| Gesture types | hug, thinking, smile, morning, goodnight, proud, support, thanks, lucky, miss_you, miss_together, miss_home, miss_kids, miss_pets |
