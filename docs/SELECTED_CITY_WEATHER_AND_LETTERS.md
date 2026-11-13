# OneSpace — City-based weather and Couple Letters

**One Life. Two Places. One Space.**

## Weather
- The phone clock and time zone remain automatic.
- Profile → Weather city → **Choose a city** searches Open-Meteo's geocoding catalogue, with name, region and country shown to disambiguate results.
- Each person explicitly selects the city *they want to monitor*. **The app does not access saved locations in other weather apps.** No GPS, location services, address book or coarse/precise location permissions are needed.
- The selected city is stored as its public city-centroid coordinates, Open-Meteo city ID and a human-readable label; these represent the city, **not the person's live position**.
- Today displays each partner's selected city, temperature, weather conditions, today's high/low and rain probability. Auto refresh is throttled to approximately 45 minutes while the app is foregrounded; no background tracking.
- Changing the city fetches today's conditions before committing the selection. Failed fetch keeps the prior setting; old permission-derived city snapshots are no longer shown as selected cities.
- **Stop sharing** hides the city/weather from the paired partner while retaining the chosen city ID for convenience; re-selecting resumes sharing.
- API source: Open-Meteo (geocoding based on GeoNames). Attribution is visible in Today. Commercial/public use must obtain suitable data licensing.

## Connect → Letters
- Actual inbox, sent letters, private drafts and an editor. Letters have a title/body and immutable send timestamp.
- Drafts are visible only to their author. They may be edited or deleted until sent; publishing requires nonempty message.
- Sent letters are visible only within the paired space, **immutable after sending**, and may receive replies. Reply references are restricted by composite space ID foreign key.
- The recipient opening a sent letter writes an individual immutable read receipt. The sender sees whether their partner has marked it read. No fake push alerts or delivery assertions.
- Table and read-receipt policies are protected by RLS and explicit grants. All writes are scoped to authenticated space membership. Nothing is publicly published.
- No existing user data is reset.

## Testing
- Repeated city names in different states, no-results, network outage, choosing/change/stop, two authorized accounts, weather stale warning, no location permissions.
- Draft visibility and deletion, send, immutable sent letter, reply under same space, recipient-only read receipt, denying unrelated spaces, multi-device viewing.
- Analyze/tests, signed Android APK, correct package ID and actual GitHub Release asset.
