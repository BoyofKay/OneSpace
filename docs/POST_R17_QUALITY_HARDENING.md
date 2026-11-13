# OneSpace — Post-R17 source-only quality hardening

**Not in the R12–R17 APK. No release/build trigger. No migration or data reset.**

## Separation of versions
The R12–R17 APK build was initiated from commit `b946024327d59331671980f3abe644df91dc1e5f` (run 43451873921). All changes documented here were committed afterward. Do not assume they are in the APK the two testers are installing.

## Improvements now committed
- **Global Search reliability and performance.** Eleven RLS-protected search sections are independently guarded, so one source error no longer hides all other results. Restrict query length to 100, search at most 12 rows per section, debounce typing for 500 ms, and stop stale network responses from overwriting a newer query. Escape literal ILIKE wildcard characters. Exclude archived objects in applicable sections. Keep results scoped to the current authenticated account and avoid navigating without an ID.
- **Stable notifications.** Reuse one realtime stream per active account in the bell and notification inbox rather than recreating subscriptions on every rebuild. Distinguish travel, occasion and experience notifications with contextual icons. On compact layouts, the unread filter and Mark all read action wrap without crushing text.
- **Two-phone occasions.** Live updates for occasion plans and preparation steps, debounced refresh, revision history, stale-response rejection and proper subscription cleanup. Preserve private-plan RLS and existing audit history.
- **Trip navigation and account safety.** Reject outdated list/detail responses when account or space changes; dispose of old Realtime channels; open direct trip notifications even when their target is not among the first 200 list rows. The backend remains authoritative for authorization.
- **Resilient detail pages.** A temporarily unavailable conversation or revision-history lookup does not blank out an otherwise accessible trip or occasion. Keep previously loaded sections when one refresh fails; show a retry warning. Trip history fetches only fields that the collapsed history UI actually uses, not large before/after JSON snapshots.
- **Date accuracy.** Occasion saving/preparation lead times use calendar-day field arithmetic, rather than subtracting a fixed number of 24-hour durations (DST protection). Cross-year and leap-day rules are retained.
- **Shared-space cache integrity.** An in-flight older membership request cannot overwrite a newer seeded account/space snapshot or the result of a refreshed membership lookup.
- **Responsive form design.** Two-field groups in occasion setup, budget/step editing and itinerary expenses stack on narrow screens or when text scaling requires more width. Trip and occasion action headers wrap. Global Search gains a sensible maximum reading width, clear-search affordance, keyboard dismissal, and empty-state guidance.

## Focused QA to perform with the NEXT APK, not the current R17 build
1. Type rapidly into Search, replace the search term and clear it. Results must never show the previous term. Search literal % and _ characters without returning unbounded matches.
2. Disconnect/reconnect internet while searching: show a useful warning, not a blank/error screen. Verify results never include a partner's private objects.
3. Open notifications repeatedly and switch between unread/all. Confirm no duplicate notifications, excessive spinners or subscription storm.
4. Create a shared occasion on Phone A and edit/complete a preparation step on Phone B. Verify both devices converge without losing previously loaded history.
5. Create a private surprise plan on A: B must not see it or its steps in list, Search, Calendar, Today or notification routes.
6. Edit and archive a shared trip on B while A displays its itinerary. Confirm refreshing, deep links, and archived/recoverable entries still work.
7. With slow or intermittent network, verify a failure in the optional history section does not prevent viewing the trip or occasion details already loaded.
8. Check birthday/anniversary preparation dates crossing an expected DST boundary in Pennsylvania, as well as dates spanning a year boundary. Dates must not shift by a calendar day.
9. Rotate narrow Android devices and increase font scaling to 150–200%. Budget/currency, prep/saving, notifications and Search must remain readable without horizontal overflow.
10. Sign out and back into one authorized account (without uninstalling/clearing data). Old account/space content should not flash during refresh.
11. Verify both old accounts, memberships, photos, letters, trips, activities and other records are still present before and after testing. No destructive cleanup is permitted.

## Verification and release policy
- All modified Dart files passed lexical delimiter and relative-import existence checks in this source-only iteration.
- Regression-test source was added for literal search queries, DST-safe lead times and responsive form layout; **these tests have NOT been executed** for the post-R17 changes.
- Flutter analyze, Flutter test, Android compilation, signing and two-phone acceptance remain future quality gates for this next candidate.
- **Do not** update `release/READY_TO_BUILD.md`, invoke CI or publish another APK until test feedback from the existing R12–R17 APK is reviewed and the user requests the next release.
- No database migrations, auth resets, saved-data cleanup or deletion were performed for this hardening batch.
