# R78 — Share from Maps, places map, counters visuals

Require-Firebase-Config: true

Previous signed preview: 0.1.442 (R77).
Preserve the existing com.onespace.onespace.preview Android package,
same signing certificate, Firebase config, biometrics, all account and
partner pairing data, checklists, notes, memories and user documents.
INSTALL AS AN IN-PLACE UPDATE only. Never uninstall or clear data.

## Included since 0.1.442
- Share a place from Google/Apple Maps into Our places (been there or bucket list), with its pin.
- Our map (OpenStreetMap): pins for every place, a small map on each place page.
- Counters: the day itself vs its anniversary, progress bars, a Today line, age bars for past dates, linked dates drawn on a line.
- Our places and Counters on the Today shortcuts.

## Database
- 0131_r78_place_coordinates (applied 16 Nov).

## Verification
- "Verify OneSpace iteration" and "iOS build" passed on r78-places-map-counters (new packages flutter_map 8.3.2, latlong2 0.9.1).
