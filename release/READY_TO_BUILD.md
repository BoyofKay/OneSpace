# R84 — opt-in counters and meaningful map markers (QA build)

Require-Firebase-Config: true

QA app (package onespace.qa), QA backend. In-place update over OneSpace QA 0.1.449.
Production app (live.onespace.app) is NOT released by this change.

## Implemented
- Counters tab includes only saved counters. No automatic special dates, occasions, events,
  reunion dates, trips or flights.
- Calendar events, birthdays/anniversaries and saved special dates, occasions, trips,
  flight options and dated itinerary elements: Add to counters in ⋮ opens the
  existing full-page counter editor prefilled, but does not save without user action.
- The New Counter editor offers a picker for existing dated records.
- Saved counters are independent editable date snapshots. Source privacy is respected
  when prefilling the new counter.
- Our map: distinct circle/coral (visited) and square/teal (bucket list) with category
  symbols, plus partner-colored visibility initials and an explanatory legend.
  Mini maps show category symbols too. Original pin-by-tap/long-press still works.

## Verification
- Branch r84-opt-in-counters-map-markers: Flutter dependency check, static analysis and
  full automated tests passed on GitHub run 44172907924.
- Two-phone acceptance checklist: docs/R84_QA.md.
- No database schema or data migrations required. No production build requested.

## Distribution
- OneSpace QA 0.1.<GitHub workflow run number> APK in Releases / Actions Artifacts.
- Install over the existing QA app on both phones; do not uninstall or clear data.
- Only prepare the production Play bundle after both phones pass QA.
