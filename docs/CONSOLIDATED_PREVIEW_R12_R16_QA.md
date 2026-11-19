# OneSpace — consolidated private Android preview (R12–R16)

## Status
**Source committed, database migrations deployed, NOT yet a compiled, signed or phone-accepted APK.**
No GitHub Actions were dispatched for R16; the release marker at `release/READY_TO_BUILD.md` must remain untouched until a single full validation build is authorized. The existing downloadable preview 0.1.395 predates R12–R16.

## Why these changes belong together
This bundle closes gaps in the “Two of Us. One Space” vision:
- R12: stand-alone saved contacts, collapsible contact cards, link-to-origin only where applicable, editing/history, readable Daily Check-Ins, Letters fixes, expanded editable gesture pools.
- R13: shared movies, TV, music, books and games; suggested/planned/enjoyed statuses; partner-specific reviews and conversations; notifications, To-day agenda.
- R14: Trips & Journeys; itinerary, flights/hotels/bookings, partner collaboration, archive, audit, currency-aware costs and travel countdowns.
- R15: private travel-document PDFs/photographs with authorized signed previews, archiving, per-trip file policies, native OS document picker.
- R16: Android Share to OneSpace and manual Save Link; file into a new/existing Coordinate Activity or Shared Experience; optional comparison option (price, specs, currency). Occasions & Surprises with preparation and saving lead times, private gift planning and steps. Daily selfie and photo memories with grid, featured, Polaroid and overlap layouts.

## Contract that must not be broken
- Keep both authentication accounts, their existing pairing, the single shared space and every existing record; do not reset test data.
- Allow only non-destructive schema migrations where existing rows are carried forward.
- Privacy is per object: Only me must remain invisible to partner, search, Today, media buckets and notifications; shared items are collaborative.
- Keep one account per phone, with Android biometric/device credential sign-in and session controls; do not reintroduce account switching.
- No changes to package ID or stable preview certificate. Confirm upgrade installation without uninstalling.
- No silent data submission: Android shared text stays local until the user chooses a destination and saves.
- Never publish a public production release from this development branch.

## Essential on-phone acceptance (both devices)
1. Install new signed APK over 0.1.395 **without uninstalling**. Confirm existing logins, PIN/biometrics, pair, and existing Activities survive.
2. Launch both devices and verify Today loads within reasonable time, without a black/red error widget, and navigates correctly across all five tabs.
3. Open saved contact cards, edit, collapse, restore; for Activity-origin cards, only the From link should navigate to Activity.
4. Record personal feeling and request/respond to a partner check-in; verify privacy, log readability, and in-app notifications.
5. Add/edit a gesture message; verify manual pool, thoughtful ritual pool, not just the visible first three presets.
6. Read sent and received letters, reply, and verify read receipts.
7. Suggest/plan/enjoy Shared Experiences; add separate ratings from the two accounts, comments, and verify partner notification routing.
8. Build a shared trip and a private trip. Verify private trip invisible on partner phone and in search; shared itinerary syncs without time shift.
9. Attach PDF and image to shared trip; signed preview works on both phones. For private trip, partner may not list/view even with known file path.
10. Archive/restore travel files and itinerary items; actual bytes and older data remain.
11. Android: from Chrome/Amazon/Target-like browser Share menu choose OneSpace. Confirm it proposes saving a link, does not auto-publish, and supports a comparison option with price/specs.
12. Attach an incoming link to an existing Activity; inspect components, activity conversation, reactions and comparison.
13. Create a private Activity from an incoming link; verify the partner cannot find it. Explicitly share a different Activity and verify the partner sees it.
14. Verify manual Save a link or idea option works even without Android Share; iOS native Share extension remains a separate task.
15. Create private holiday/birthday plan, lead time 30/60 days, budget and preparation steps. Partner must not see the plan, steps, notifications, or upcoming schedule.
16. Create shared occasion; partner receives in-app notice. Due occasion, saving start, prep start and individual steps appear in Coming Up Together within next seven days.
17. Add daily selfie photo, then several images to collage memory; switch photo layout, preview, caption, archive/restore on both devices.
18. Share a private memory by existing explicit view-only grant; recipient sees only authorized photos, cannot alter the content. Revocation closes access.
19. Check Global Search for Activity, trip, travel document, experience, and occasion; verify correct deep links and RLS visibility.
20. Exercise offline/slow network/retry, layout on small Android screen, screen reader, landscape, Arabic/English settings, and notification tap.
21. Inspect privacy policies with two independent accounts, including direct URL attempts on private signed media.
22. Verify no changes to existing account rows, membership rows or pre-existing content counts after installation.

## Build gate — ONE consolidated APK
A. Before touching the release marker, run Flutter analyze, all Flutter tests, Android native compile and app integration tests.
B. Resolve analyzer/test errors **in source only**; no repeated release builds. One validation job when quota is available and specifically authorized.
C. Then update `release/READY_TO_BUILD.md` exactly once for R12–R16 and create one optimized signed Android preview build. Verify stable package ID and signing certificate.
D. The APK is retained in GitHub Actions Artifacts. GitHub Releases publishing is attempted once; an HTTP 403 must not trigger three retries or discard the signed binary.
E. Verify the actual APK download, install it over the older preview on both Android devices, and record acceptance defects before publicly advertising this version.

## What remains outside this bundle
- iOS native Share extension and full Xcode/device build testing (Android manual share intake works; iOS can manually paste a link).
- Actual OS push notification delivery and guaranteed background alarms; in-app notifications/agenda are distinct.
- Phone-calendar bidirectional syncing, Netflix/Spotify/Amazon account syncing, automatic flight status/PNR parsing.
- OS lock-screen emergency integration or emergency service dispatch, which require special platform/privacy review.
- Automatic currency conversion (estimates deliberately stay in original currencies).
- Permanent deletion policy for shared memories is intentionally unresolved, so all removals are reversible.
- User-entered content is not translated; UI internationalization is independently configurable.

## Security / process
- DB migrations through 0069 (R16 photos) applied; no destructive cleanup.
- Storage buckets for travel documents and memory photos are private and restrict read with RLS.
- Source-level delimiter and import/path checks are **not the same as compilation**.
- There may be code/runtime integration defects until the one actual build and two-phone tests are executed.
