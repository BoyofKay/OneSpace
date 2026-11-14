# R43 — Consistent History, Filters and Local Search

Require-Firebase-Config: true

Previous signed preview: 0.1.416 (R42 shared mentions and content search).
Preserve the existing com.onespace.onespace.preview Android package,
same signing certificate, Firebase config, biometrics, all account and
partner pairing data, checklists, notes, memories and user documents.
INSTALL AS AN IN-PLACE UPDATE only. Never uninstall or clear data.

## New R43 scope
- Top-right History and Filters for Trips, Occasions, People & Contacts
  and Shared Experiences. Embedded Coordinate tab gets top-header
  History/Filters without a nested AppBar.
- Check-ins has top History for partner conversations plus top filters
  for invitation status and journal visibility.
- Search across trip origins/destinations/notes, occasion honorees/
  planning notes, experience titles/platforms/descriptions, contact
  fields, activity descriptions, check-in conversations and gratitude.
- Shared, tested RecordCollectionSearchRules supports multiple search
  words across visible metadata fields and isolates archived-only rows
  from active collections without changing backend authorization.
- Restoring an archived item continues to use existing record actions.
  Edit/revision history remains distinct from archived History.
- All R34 legacy/new checklist expansion, R37 voice, R38–39 Notes
  links/backlinks, R40 audit/contrast, R41 shared mentions and R42
  global full-content search are preserved.

## Verification
- Additive database changes: NONE for R43.
- Full Flutter analyzer, test suite and new search/history rule tests
  SUCCESS, run 60 at source SHA 6f277888cf11e84846ebc40ba18cc3a56659a3cd.
- Android signed pipeline must independently repeat source checks,
  compile Kotlin, validate Firebase, package ID and signing cert, and
  publish one verified signed APK.
- R42 signed preview 416 is pinned to earlier source separately.
- Check docs/R43_COLLECTION_HISTORY_FILTERS_SEARCH_QA.md before
  claiming device acceptance.

## Two-phone validation
1. Update without data reset and test six upgraded screens.
2. Find top History, Filters, local search; confirm active and
   archived records stay separated and correct objects are restored.
3. Check private notes, surprise occasions and check-ins never
   appear for the other partner.
4. Ensure exact task notification deep links, shared Reminder @mention
   alerts, R34 checklist expansion and voice readout still function.
5. Check themes including seasonal appearances, large font scaling and
   dark backgrounds with real phone screens.

Controlled R43 signed preview candidate, November 14, 2026.
