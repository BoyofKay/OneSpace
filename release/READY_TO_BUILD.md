# R67 — Trips, Occasions & gifts, note formatting

Require-Firebase-Config: true

Previous signed preview: 0.1.433 (R66).
Preserve the existing com.onespace.onespace.preview Android package,
same signing certificate, Firebase config, biometrics, all account and
partner pairing data, checklists, notes, memories and user documents.
INSTALL AS AN IN-PLACE UPDATE only. Never uninstall or clear data.

## Included since 0.1.433
- Trips: first-step setup (airports by code, one way/round, who's traveling, passengers), automatic status, Google Flights prefilled search, flight share-in/paste, bags & seat, documents first, ⋮ everywhere.
- Occasions: start from a holiday or special date, prep reminder, automatic status, redesigned page; gifts grouped with ⋮ (Reserve, Mark as purchased), Use this list.
- Notes: friendly formatting bar.

## Database
- 0121_r67_trips (applied and tested): trip setup columns, flight bags/seat, automatic trip status (+ hourly cron).
- 0122_r68_occasions (applied and tested): occasion source, automatic occasion status (+ hourly cron).

## Verification
- "Verify OneSpace iteration" passed on r67-trips-occasions.

## Two-phone validation
Follow docs/R67_QA.md.

Controlled R67 signed preview candidate, November 15, 2026.
