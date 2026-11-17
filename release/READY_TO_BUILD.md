# R82 — phone calendar and map diagnostics (QA build)

Require-Firebase-Config: true

QA app (package onespace.qa), QA backend. In-place update over qa-0.1.447.

## Fixed / improved
- Phone calendar: a failed write is now reported to us and shown as "could not write" (it used to look like a
  permission problem); events are written in smaller chunks; Settings explains where the OneSpace calendar appears.
- Map: tiles identify the real app (onespace.qa / live.onespace.app); failed tiles are reported and the map says so.
- Place search ("Find") uses the OpenStreetMap-required identification and reports failures.
- Error reports carry the real build number (0.1.N-qa) and automated tests no longer write into the QA database.

## Verification
- "Verify OneSpace iteration" (flutter analyze + flutter test) passed on r82-calendar-map-diagnostics, 17 Nov 2026.
