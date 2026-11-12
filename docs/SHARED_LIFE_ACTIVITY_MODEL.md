# OneSpace — the Shared-Life Activity Model
**Architecture baseline, 13 November 2026.** This document is a product and implementation plan, not functionality already shipped.

## Original promise, restored
**One Life, Two Places.** Three pillars: **Remember · Coordinate · Connect**. Original experience areas: Our Day, Commitments, World, Entertainment, Memories, Journeys. The original **commitment loop** was: *request → accept → research/add links → review → select/purchase/postpone*. The original M01–M22 catalog remains a capability backlog, not 22 navigation destinations.

The app must not become a generic task/calendar/notes bundle. Partners need a persistent space where they can jointly make decisions, capture the reasoning, exchange experiences, and remember what happened across different time zones.

## Canonical model
**Activity** = one enduring purpose (e.g., *Find a heater*, *Find gymnastics classes*). It begins with a **title** and optionally a **body**, with immutable author and original creation time. It can grow through connected child records, each attributed and time-stamped:
- **Comments:** chronological conversation, reply threads, target links to an Activity, Option or Step; no silent overwrites.
- **Edits/revisions:** partners may revise the current Activity title/body; preserve original text, all subsequent versions, actor, UTC date/time, and a readable before/after diff.
- **Options/findings:** comparable candidates with source URL, screenshot, store/provider, observed price/currency/date, specs, reviews with source, and free-text notes. Do not imply manually recorded prices are live.
- **Opinions:** independent like/dislike/neutral reactions on each option; reactions never constitute a joint decision.
- **Steps:** optional nested actions created at any time, with assignee, status, result, deadline if wanted, supporting evidence. An Activity does not require steps.
- **Decisions/outcomes:** chosen/rejected candidate, why, by whom, when; purchased/returned, registered/withdrawn or postponed/cancelled, all reversible with history.
- **Evidence:** screenshots/photos/files stored privately and attached to the relevant Activity, Option, Comment, or Step. Partner authorization is checked for all reads, signed URLs and uploads.
- **Activity feed:** interleaved comments and meaningful change events with optional type filters. Preserve original timestamps; render local time to each viewer.

*Activity* is the container. *Option* is a research candidate. *Step* is a unit of work. *Comment* is a conversation item. *Memory*, *Check-in*, and *People/World reference* can also exist independently and be linked to an Activity when helpful. Avoid creating a universal Task object and renaming it.

## Acceptance: finding a heater
1. A creates **Find a heater** with body and immutable authorship.
2. A attaches Amazon and Walmart options: links, screenshots, observed prices, reviews/specs and notes.
3. A comments *Don't forget these*; B replies *I'll look after work*.
4. B dislikes both and updates body to require **timer and automatic shutoff**. Original body and edit history remain accessible.
5. B adds a third option and comments specifically about voltage. A replies and likes the candidate.
6. B chooses candidate 3. They record the reason. Later B marks **Purchased**, with optional price paid/receipt and eventual **Delivered**.
7. Every original link, screenshot, opinion, comment, old body and decision stays visible under the Activity as authorized.

## Acceptance: finding gymnastics classes
1. A creates **Find gymnastics classes**.
2. Partners add 3 providers and compare **age range, dates/times, fees, parent attendance, swimming, trial classes, websites and travel context**.
3. B creates step **Email three places** and marks provider-specific emails sent. Replies are attached as evidence under the relevant provider.
4. The couple discusses the responses, adds an in-person visit with a date/time-zone and completes that step.
5. They choose provider B, record why, then complete the **Register** step. Activity outcome is **Registered**.
6. All information remains searchable; none disappears simply because the Activity is done.

## Experience architecture
**Bottom tabs (target): Today | Activities | Together | Memories | World**
- **Today:** Our Day/My Day, clocks, moments that matter, reply requests, recent partner updates, next decisions, upcoming commitments.
- **Activities:** the collaboration engine; Waiting for me / Updated by partner / Comparing / Decided / Completed. Start with minimal title/body; optional templates thereafter.
- **Together:** check-ins, connection, shared rituals, entertainment and conversation prompts.
- **Memories:** original stories, photo albums, shared occasions and recollections; protect each author's contribution.
- **World:** people/family context, travel/reunions, safe knowledge library and references.
Calendar access is contextual (Today, Activity, global search), not the app's identity. Activity inbox, search and profile appear in the header. Existing Tasks/Lists/Notes/Goals/Calendar remain available during migration.

An Activity detail page must show: **original byline; current body; options/comparison; optional next steps; conversation & changes; explicit decision/outcome; edit history**. No part of the detail should be gated by an unnecessary assigned-to/due-date field.

## Suggested database entities
`activities`, `activity_revisions`, `activity_comments`, `activity_options`, `activity_option_reactions`, `activity_steps`, `activity_attachments`, `activity_decisions`, `activity_events`, `activity_reads`. Prefer structured, type-aware attributes for options; use server timestamps, backend-protected audit, optimistic concurrency and parent-inherited RLS. A revision and its content edit must be **atomic**.

## Specializations, not separate apps
- **Shopping/Compare:** merchant, price, currency, specs, reviews, shipping, purchase/delivery outcome.
- **Find/Enroll:** provider, age, classes, schedule, requirements, emails, visit, registration.
- **Travel/Journeys:** flights, hotel, itinerary, people, bookings, local times, documents.
- **Choose:** alternatives, criteria, personal preferences, jointly recorded outcome.
- **Remember/World:** contextual people, contacts, documents, life history, saved knowledge.
- **Experience/Together:** celebration, relationship moment, activities and reflections.

Templates configure optional fields, evidence types and typical stages, but users can choose a blank Activity. Stages are flexible; *Purchased* is not a valid universal end state for all Activities.

## Security and preservation
Equal partners. Shared Activities collaborative. Private Activities creator-controlled. Revocable view-only access must never imply commenting/editing rights. Child records inherit the parent's RLS permissions. Author IDs and time come from the server; no personally identifying data in public previews/notifications. Attachments require a private bucket with size/type checks and short-lived access. Preserve both partners' histories. Shared Memories require **both partners' approval** for permanent deletion. All old data remains available through the transition.

Original constraints: English/Arabic UI independently per account, preserve author-entered text without machine translation; Android then iOS parity; hybrid external/native integrations; native Android share-in for links and images; security and acceptable phone performance.

## Delivery gates
0. Fix existing CI lint/build failures; keep the preview signing identity stable.
1. Add an Activity core with author/time, title/body, atomic edits/revisions, secure RLS and an Activity detail screen.
2. Add contextual comments/replies, options, source links, notes, price/specs, reactions, comparison, decision history.
3. Add secure screenshots/photos, Android share-to-OneSpace, steps, contacts/emails, date/time-zone and outcomes.
4. Move the navigation, Today dashboard and unified activity inbox to the new interaction model without data loss.
5. Expand World, Memories, Entertainment, Journeys, AI-assisted recall and privacy-safe reminders.

**No full release until both concrete heater and gymnastics flows pass two-account Android tests.** Existing object screens cannot simply be removed or relabeled; this is a new shared-life interaction model.
