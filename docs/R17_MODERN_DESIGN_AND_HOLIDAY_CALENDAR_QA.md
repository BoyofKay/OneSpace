# R17 — Modern design, seasonal themes and calendar occasions

## Implemented in source (not yet a compiled APK)
- Four independently selectable Material 3 color collections: Coastal Blue, Rose & Plum, Sage & Sand, Midnight Indigo.
- Light, dark or Follow Phone brightness, using the OS appearance setting. Preferences are local to each device, do not overwrite a partner's data, and do not require network or login.
- Consistent shape/touch-target language for AppBars, cards, chips, inputs, primary actions and navigation. Dark theme uses semantic foreground/background contrast.
- Wide screen (900+ logical pixels): NavigationRail and centered content with a maximum content width. Narrow phones: original five-tab bottom navigation.
- Responsive two/four-column theme selector and small-screen safe brightness controls.
- Subtle, optional seasonal accents: Valentine's (Feb 10–15), spring (Mar–May), Halloween (Oct 25–31), winter holidays (Dec 18–Jan 2). Manual preview and Off are available. No distracting automatic fullscreen animations.
- Seasonal banner on Today and Shared Calendar; animated changes honor phone reduced-motion settings.

## Calendar integration
- Shared, opt-in holiday sources for US, Egypt, Saudi Arabia, stored in RLS-enabled `space_holiday_sources`. No automatic subscriptions at migration time.
- US and Egyptian **national** public holidays are pulled from Nager.Holidays community API v4 and cached in memory for seven days. Some state/subdivision holidays are intentionally omitted to avoid misleading national availability claims.
- Saudi Arabia uses **only** known fixed civic dates (Founding Day Feb 22; National Day Sep 23). These are date labels, not a claim about adjusted employer/agency days off. Lunar/Eid dates are not guessed; user can add the confirmed dates using a personal special occasion or calendar event.
- Holiday overlay does **not** create `space_events` or `occasion_plans` rows and cannot delete or change personal occasions.
- Personal occasion plans are RLS filtered from existing `occasion_plans`, displayed in month/week/day calendar with separate markers, label, annual recurrence and navigation to existing detail.
- Quick Birthday, Anniversary and Special day buttons prefill the selected date/type; the editor supports a named honoree, privacy (Only me / Both of us), optional budget, saving/preparation lead times, and preparation checklist. Existing plans remain valid (new honoree field defaults empty).
- Imported holidays do not appear as editable personal events. Provider/network failures leave original calendar usable and show a descriptive partial-data warning.

## Design and usability acceptance
1. On both Android phones, test each theme in Light, Dark and Follow Phone. Toggle Android system dark mode with Phone selected and confirm colors follow it.
2. Theme on phone A must not change phone B. Relaunch app and confirm preference persists without touching either account.
3. Use 320, 360, 393, 600, 900 and 1200 logical-pixel widths where possible. No clipped buttons, text overflow, off-screen controls or horizontal-scrolling main content. At >=900 confirm side rail; on phones confirm five bottom tabs.
4. Use text scaling (up to 200%), Arabic RTL and Android screen reader. Check themed cards, labels, selected states, error surfaces, touch targets and screen reader order.
5. Turn on reduced motion. Animated theme transitions should be minimized or disabled by the platform if supported; avoid flashing/pulsing.
6. For each seasonal setting Off/Auto/manual, verify banner appears only as configured, does not obscure notifications or agenda, and remains legible in dark mode.
7. Opt into US + EG holidays from phone A, confirm phone B sees the same selected countries. Check a national holiday in month, week and day. Unselect one and confirm only its overlay disappears.
8. Add a Saudi civic source; verify February 22 and September 23 are displayed as civic dates without claiming Eid or observed employer holiday dates.
9. Force network failure: US/EG holiday load must not blank, block, or destroy calendar events. Retry later.
10. Create a shared birthday and anniversary with named honorees; verify on both phones including selected-day view and existing Today Coming Up logic.
11. Create a private special occasion/gift plan; it must remain absent from partner's calendar, notifications, search, and Today. No visible seasonal change may leak a private occasion to partner.
12. Create a Feb 29 annual birthday, check its behavior in a non-leap year; adjust product policy if partners prefer March 1 rather than Feb 28.
13. Check holiday source toggles with both accounts concurrently, duplicate inserts and offline retry without losing previously saved events.
14. Confirm there are still two test accounts, two memberships, one space, preexisting Activities, and that no existing date or theme setting was deleted.
15. Verify only one later release marker update/build is used for the entire R12–R17 bundle.

## Explicit limitations
- This is not bidirectional Google Calendar, Apple Calendar or Outlook synchronization. Existing calendar UI integrates external regional holiday overlays **visually**.
- Regional-holiday data availability depends on the public provider; provider terms and production suitability require review before public launch. Source: https://nagerholidays.com/api
- US holidays are national only (not Pennsylvania-specific) and Saudi lunar holidays require official dates; no guesses, no guaranteed closure or days off.
- Automatic holiday color themes are decorative and locally timed, not linked to religious identity, nationality, or partner preference.
- No new physical-device screenshots or performance metrics have been collected.
- No Flutter analyzer, Flutter tests, native compile, real screenshots, keyboard-screenreader device QA, or APK builds were run during this source iteration.

## Build gate
Combine R12–R17 in **one** Android release only after a compilation + test suite pass. Keep `release/READY_TO_BUILD.md` unchanged until build authorization. A GitHub Release publishing HTTP 403 must not consume retry attempts or discard a signed artifact.
