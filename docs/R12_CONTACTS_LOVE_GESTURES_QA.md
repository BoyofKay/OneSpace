# OneSpace R12 — Contacts, gesture pools, love, letters and check-ins

## Built
- Contacts in Remember may be standalone or derived from Activity components;
  standalone contacts do not create an Activity in the background.
- Same full-page contact editor for both sources: name, person, phone, email,
  address, working hours, Notes; direct contacts have Only Me switch.
- Contact cards collapse/expand by tapping the card heading. Edit pencil
  opens the contact editor. Origin activity opens only from clickable From.
  Standalone cards show non-clickable Created by.
- Top header History rather than duplicate Add Person shortcut.
- Soft removal, Recently Deleted filter and Restore for both sources.
  Standalone contact archive records 30-day purge-eligibility timestamp
  and immutable edit/remove/restore revisions. **No automatic irreversible
  purge is enabled** until deletion consent is decided. Existing Activity
  component audit remains in effect.
- Check-in journal and request/response logs have expandable cards,
  distinct date, mood, privacy, thoughts, gratitude, topic and response data.
- Gestures: sending screen contains only gestures to send. Custom creation
  and editing live in Settings. Settings groups 13 gesture types into
  expandable message pools, counts active messages, permits edit/hide of
  built-in messages and edit/delete of personal variants.
  Sender randomizes over active built-in variants plus custom messages of
  the same type; avoids immediately repeating the last sent text.
  Morning, support/after-work and goodnight each include their original ten
  backend ritual phrases alongside three UI presets (13 built-in choices).
  Edited/hidden presets affect both manual sending and scheduled delivery;
  explicitly scheduled custom messages of the same type join the ritual pool.
- You Got This and Miss Us Together use recognizable 💪 and 👩‍❤️‍💋‍👨
  artwork in matching colored circles. Gesture notifications show the
  same type-specific icon; received gestures retain their dialog.
- Thoughtful Little Rituals is separate in Settings (morning, after-work,
  bedtime), not mixed into gesture message administration.
- One A Little Love entry appears in Today.
- Days Off editor no longer asks for individual bedtime/wake overrides.
  Existing overall sleep schedule and workday-off behavior remain.
- Letters: sent/received detail fetches a fresh authenticated record by
  ID; read receipt and reply lookup failures cannot block reading the main
  letter, and detail has explicit retry feedback.

## Two-phone acceptance
1. Create a standalone shared Contact. Confirm that no new Activity exists;
   edit from the pencil and inspect Created by.
2. Create an Activity Contact component; edit from Contacts and navigate back
   to the original Activity only via From.
3. Add a private contact and verify partner cannot see it.
4. Expand/collapse cards, search Notes, soft-remove and restore a direct and
   Activity-derived card; inspect revision audit.
5. Create a private and a shared check-in, send partner request, respond.
   Inspect expanded logs and privacy.
6. In gesture Settings, expand every type and verify the active count,
   including 13 initial presets for morning, support/after-work and goodnight.
   edit/disable one default and add one custom in the same type. Send many
   times; confirm randomization includes both sources, never disabled text.
7. Confirm custom editing never appears in A Little Love sending view;
   open the Today shortcut.
8. Confirm thoughtful ritual settings appear separately and workday-off
   editor has no custom sleep time controls.
9. Send and receive Letters on two phones; open each from Sent and Received;
   confirm read receipt does not prevent opening and that replies can open.
10. Confirm gesture icons in in-app notification list and popup.
11. Android back navigation, keyboard fit, loading performance, narrow screen
    text sizes, and no new private-data leakage.
12. Verify signing and package ID of final APK. No public launch until
    both phones pass acceptance.

## Caveats
- No phone push transport is added here; notifications remain in-app.
- Automatic gesture delivery has its established server-side ritual source;
  per-user edits to 13 preset messages are honored by automatic rituals
  as well as manual sending. Only explicitly scheduled custom messages can
  be automatically delivered; unscheduled custom messages remain manual-only.
- 30-day eligible-for-purge metadata does **not** imply the system silently
  hard-deletes shared contacts. The irreversible deletion policy is pending.
