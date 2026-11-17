# R84 — Counters are opt-in; clearer places map

## Product rule
**Counters are a personal/shared choice, not a mirror of every dated object.**
The Counters screen loads only non-archived rows saved in `space_counters`. It must NOT independently create/display birthdays, anniversaries, custom special dates, calendar events, occasion plans, trips, flights, or reunion dates. Other features retain their own date display and reminders.

## QA — add from the source
1. Open Remember → Counters. Confirm existing **saved** counters remain; unrelated upcoming dates are not injected. Refresh; nothing appears until the user creates a counter.
2. Create a Calendar event with a date → event `⋮` → **Add to counters** → full **New counter** editor (title/date prefilled). Cancel: no counter. Repeat and Save: one counter appears.
3. Occasion plan (list and detail) → `⋮` → Add to counters. Annual occasion defaults to Every year; privacy defaults to source visibility.
4. Settings → birthdays, anniversary and special dates: each saved date's `⋮` → Add to counters. Verify correct date and annual behaviour.
5. Trip (list and detail) with leaving date → `⋮` → Add to counters. A trip *without* a date must not offer a misleading action.
6. Flight option with departure date → `⋮` → Add to counters. Try private trip and verify resulting counter defaults to **Only me**.
7. Dated itinerary item (including flight) → `⋮` → Add to counters.
8. Counter **+** → **Choose from calendar, dates, occasions, flights or trips** → grouped list of dated entries (including existing last/next meet). Pick a record; verify the counter editor is filled and can Save without extra changes.
9. Edit any source after saving its counter. The counter is an **independent snapshot** and must not silently change. Remove the source: the saved counter remains. Repeating action requires a second explicit Save; it should never happen on loading the tab.
10. Two-phone privacy: private sources never appear to the other account in the picker, and shared counters appear on both devices.
11. Calendar/Google Calendar synchronization, scheduling, push notifications, and all item history actions still function unchanged.

## QA — map
1. Open Remember → Our places → Map. Been there markers are **coral circles**, bucket-list markers **teal rounded squares**. Their central icon identifies category (e.g. cafe, restaurant, hotel).
2. Shared pins have two small differently coloured initials for the people who can see them. Private pins show the owner's initial. On a one-person space, no phantom partner badge appears.
3. Filtering, existing-pin detail, panning/zooming and long-press to create a **new pin** continue working.
4. Save an existing private place on A; verify partner B cannot see it. Save shared on A; B sees it with the two badges.
5. Open place detail's mini map; it shows the same category icon/status treatment.
6. Check accessibility labels and both English and Arabic on a small Android phone.

## Release
QA first. Never trigger production or modify Supabase schemas/data for this change. No database migration required; a counter copies the chosen source date into its own existing row.
