# R27 — Trips: Flight Research & Travel Preparation Acceptance

This is a source-verified development milestone; release APK requires its own
signed R27 build. It does not change the already-building R26 APK.

## Flight research
1. Open World → Trips and create or select a trip.
2. Under **Flight research & comparison**, choose **Search Google Flights
   externally**. It opens a browser. OneSpace does not scrape prices.
3. Save two realistic candidate flights with different dates, currencies,
   stop counts, baggage and personal preference scores.
4. Select both comparison checkboxes. Confirm the comparison displays
   separate alternatives and per-currency ranges, **not a combined fare**.
5. Mark one option Booked. Confirm no ticket is purchased automatically.
6. Use **Add to itinerary** and confirm the copied itinerary includes airline,
   source URL, booking date, currency and baggage notes.
7. Archive one candidate and restore it; private option data remains private.

## Unified travel preparation
8. Choose **Travel essentials** and **Leaving home**. Verify both appear
   in Remember → To-do and Checklists rather than a new shopping-list module.
9. Generate the same template twice. Confirm it returns the existing
   checklist without duplicate items.
10. Open the generated checklist via the Trip link and verify it is
    expanded. Edit the items to customize to the journey.
11. For a shared trip, verify each partner's completion checks remain
    independent. For a private trip, the other account must not see it.
12. Optional: generate **Traveling with baby** and **Traveling with pets**.
    Only use relevant lists and remove/customize items as needed.

## Test evidence
- RLS regression 0015: candidate flight privacy and shared collaboration.
- RLS regression 0016: linked travel checklist creation and idempotence.
- No automated booking or Google Flights price API is claimed.
- Offline encrypted document cache and hands-free read-aloud remain
  outstanding and require separate secure implementations.
