# OneSpace — Phone-driven Time, Approximate City & Weather

**One Life. Two Places. One Space.**

## What changed
- Time zones are read from each Android/iOS device using the OS-native IANA identifier; there is no manual time-zone selector or location choice.
- Local time comes from the device; partner time is derived from the time zone their phone last shared. Daylight saving follows IANA rules. The clocks refresh each minute, and settings synchronize on opening/resuming OneSpace.
- Each partner may **individually opt in** under Profile → **Share my city and weather**. The app displays a clear explanation, then uses the OS foreground location permission dialog.
- Only coarse location is requested (ACCESS_COARSE_LOCATION on Android); no precise (ACCESS_FINE_LOCATION), background location or tracking service permissions.
- On user consent, the app uses a **single one-shot location fix**, resolves it to city/region/country on the device, and requests nearby weather from Open-Meteo using rounded latitude/longitude (one decimal degree, approximately 10 km). Exact GPS coordinates or addresses are never stored in Supabase.
- Each profile stores only opt-in state, approximate city, temperature, condition code, last-updated time and native time-zone identifier. The paired partner sees these values inside Today; weather is marked potentially stale after two hours.
- Weather refresh is limited to once per 45 minutes while OneSpace is open. Failed requests never block Today.
- When location permission is revoked and the app next checks, the app clears previously shared city/weather. Turning sharing off in Profile clears it immediately upon successful server response.
- Missing location permission, unavailable system geocoder, or network failure never fabricate a city or weather. Opting out does not affect the clock.

## Privacy and provider
- **No continuous tracking; no live GPS pin or exact address.** Each partner explicitly enables sharing; the other partner cannot enable it.
- The database profiles RLS restricts updates to the account owner and reads to the paired partner.
- The Today RPC returns city/weather values **only if opt-in is enabled**.
- Open-Meteo receives rounded coordinate values for weather requests. Attribution: **Weather data by Open-Meteo.com**.
- Open-Meteo's free service is for noncommercial usage with attribution. Before OneSpace is offered commercially, evaluate licensing or a paid weather provider.
- The phone may itself use third-party geocoding services at the operating-system layer.

## Technical
- Flutter packages: flutter_timezone, geolocator, geocoding, http.
- No extra network call on the critical first Today snapshot. Optional phone/profile/weather refresh is asynchronous, throttled, and only requested after successful auth.
- Profile no longer allows manual zone selection; auto-detection is the default.
- Shared city data is not suitable for emergency location tracking.
- Physical-device tests remain necessary: permissions granted/denied/revoked, coarse city result, multiple devices, system clock zone changes, phone resume/background, cross-account RLS, daylight-saving behavior, denied network/offline, and small-screen display.
