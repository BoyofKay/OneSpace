# OneSpace — Partner clocks on Today

**Two of Us. One Space**

## Experience
- Each partner voluntarily chooses an IANA time zone under **Profile → Your time zone**. The list is searchable; no GPS/location permission is requested.
- **Today** shows the two partner clocks, time zone names, local calendar dates, and current UTC offsets. The time difference accounts for DST automatically.
- **Living together** shows one local clock rather than unnecessary long-distance messaging.
- **Living apart, same time zone** shows two clocks and flags a configuration mismatch when their saved time zones currently differ.
- **Long-distance** shows both clocks and the current hour/minute time difference.
- An unset partner zone is clearly marked **not set**, never inferred from an abbreviation, name or location.
- The viewer's clock may use the device's local time as an explicit fallback until the user configures their zone.
- Times refresh locally once per minute and require **no new network request**. The existing get_home_snapshot_v2 RPC includes the two zones in the member records; therefore startup avoids an extra round-trip.
- Changing Profile settings and returning to Today requests a refreshed snapshot.

## Security and correctness
- A time zone is personal profile data and only visible under the preexisting profile RLS policy (the owner and their paired partner).
- Only the account owner may update their stored zone. No location tracking or address storage.
- Server limits time_zone length and characters; Flutter validates against its bundled IANA catalogue. Missing or invalid zones display as unknown.
- The bundled IANA database supports DST shifts, half-hour offsets, and different calendar dates across the same UTC instant.
- No timezone is assumed based on the user's IP, GPS, or the relationship-mode choice.

## Acceptance
1. Set one profile to Asia/Riyadh and another to America/New_York; confirm the times and difference.
2. Verify the difference is 8 hours in January and 7 hours in July (US DST).
3. A partner with no zone configured shows a clear setup message.
4. Switch relationship mode across living together / apart same zone / LDR.
5. Changing profile zone and returning to Today refreshes its clock.
6. Validate that unauthenticated users cannot request the dashboard, and other spaces cannot see profile settings.
7. Check Arabic RTL and small Android screens before production.
