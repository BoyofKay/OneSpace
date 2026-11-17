# R83 — Add a place by pinning the map (QA acceptance)

Scope: **Our places → Our map**. QA first, then production only after phone acceptance.
Existing **Edit → Find** and calendar sync must remain unchanged.

## Main workflow

1. Open Remember → Our places → Map. Existing hearts and bucket-list pins remain visible.
2. Tap **Pin a place**, then tap an empty spot on the map. A pin appears at the precise tapped coordinates.
3. Tap **Been here**. The normal **New place** editor opens (not a popup), pre-selected to Been there, with latitude/longitude, and any available place name, city, country and address.
4. Enter or correct the required name; change privacy, category and optional visit date; save. The new heart appears at the pinned coordinates; it is listed under Been there.
5. Repeat by long-pressing anywhere on the map and selecting **Add to bucket list**. The normal **New dream place** editor opens pre-selected to Bucket list; save. The compass pin appears.
6. Use **Remove pin** or Cancel in the editor; no place should be saved. A name/address lookup failure must not prevent manually naming and saving the pinned location.
7. Select an existing pin → details. Switching All/Been there/Bucket list filters, panning, zooming and attribution still work.

## Regression / two-phone checks

- In a place without coordinates, use **Edit → Find**; the existing marker and message should update.
- Test existing Google Maps sharing to OneSpace, open a place mini-map, and open in Google Maps.
- Save a **shared** pinned place on Phone A; it appears on Phone B. Save **Only me** on A; Phone B cannot see it.
- Select an existing marker before creating a new pin; the cards must not overlap.
- Test Arabic UI and both a large and a narrow Android phone; confirm buttons and editor are readable.
- Verify Google Calendar's existing OneSpace calendar remains visible when enabled; R83 does not change calendar integration.

## Release gate

R83 source passed the GitHub **Verify OneSpace iteration** Flutter analysis/tests workflow
[run 44159377150](https://github.com/BoyofKay/OneSpace/actions/runs/44159377150).
QA APK must compile and be tested on both phones before building/promoting a new production Play bundle.
No Supabase migration is required by this change.
