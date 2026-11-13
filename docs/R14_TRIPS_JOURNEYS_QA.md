# R14 — World: Trips & Journeys

## Built, committed and deployed (no APK or GitHub Actions used)
- World now has a dedicated Trips & Journeys destination instead of only a placeholder.
- Create shared or Only Me journeys, with name, origin, destination, departure and return dates, notes, progress status, archive and restore.
- Trip privacy is chosen at creation and deliberately cannot change afterward, preventing accidental exposure of booking details. No existing account or previous content was migrated or removed.
- Add editable itinerary entries: flights, accommodation, transport, activities, reservations and notes.
- Store departure/arrival dates and local clock times exactly as written on travel bookings. **The app does not convert flight times automatically**, because itinerary timestamps can refer to different localities.
- Optional provider, confirmation reference (copyable), external booking link, notes, estimated cost and three-letter currency.
- Mark individual stops complete and soft-remove/restore; travel history remains intact.
- Aggregate estimated costs **separately by currency**, with no fictitious FX conversion.
- Shared trip conversations with personal message retraction and edit-history audit for trips and itinerary rows.
- A new trip and a new trip message notify the partner **only when the trip is shared**; those notifications open the trip.
- Today → Coming Up Together includes trip departures and dated, incomplete itinerary entries in its seven-day RLS-filtered agenda. Tapping either opens the original trip.
- Global search includes trip names, itinerary entries and Shared Experiences.
- RLS protects shared and private trips and all dependent tables. Real-time subscription plus debounced reload refreshes trip summaries, detailed itinerary and conversations between devices.

## Data preservation contract
- **Never** delete or recreate the two test accounts, the shared space, or any existing activities, notes, contacts, calendar items, letters, experiences or check-ins.
- Migrations 0063 and 0064 are additive except extending notification check constraints to accept new types. No destructive data modification was used.
- Future schema changes requiring normalization must retain existing records and make a targeted transformation with a verification query.
- No irreversible purge, account reset, or automatic cleanup.

## Two-phone acceptance
1. Sign into one account on each phone; check that pairing and older content remain available.
2. Create a shared journey on phone A; confirm it appears on B after synchronization.
3. Create a private journey on A; confirm it is **not visible on B**, including in Today and global search.
4. Edit a shared trip title, dates and status from phone B; confirm the result on A and inspect the audit.
5. Add a flight with local departure and arrival dates/times, route, provider, booking ref and source link. Confirm local time does not shift across the two phones or daylight-saving changes.
6. Add hotel, transport, activity, reservation and note entries; edit, mark completed, remove, and restore. Verify old data remains in revision history.
7. Add USD and SAR costs to different items; confirm totals remain separately labelled rather than summed across currencies.
8. Add a trip conversation message on A; verify notification on B deep-links to the original trip; retract own message and check partner cannot retract it.
9. Create a trip and an unfinished dated itinerary entry within seven days; verify Coming Up Together shows each and opens its trip. Entries outside seven days should not appear.
10. Use global search for trip name, itinerary title and Shared Experiences; verify only authorized results appear.
11. Test narrow Android layouts, back navigation, slow network, unexpected offline/retry behavior, RTL and per-partner language preferences.
12. Test edit/archive/restore on both phones and ensure no previous unrelated data is altered.

## Known limitations before public launch
- Flight itineraries and booking references are structured text and links; there is **no file storage or boarding-pass upload** in R14.
- No calendar write-back, external flight status API, Google Travel import, email sync or OS push notification is claimed.
- This source has **not been Flutter-analyzed, APK-built or physically phone-tested** since the GitHub Actions quota was exhausted. The static source review does not replace those gates.
- Do not publish or install a new release until Flutter analyzer and tests, signing/package checks, and real two-phone acceptance succeed. No R14 release marker was changed.
