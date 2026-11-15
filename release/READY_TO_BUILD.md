# R48 — Notifications 2.0 and brand line in the top bar

Require-Firebase-Config: true

Previous signed preview: 0.1.418 (R46 + R47).
Preserve the existing com.onespace.onespace.preview Android package,
same signing certificate, Firebase config, biometrics, all account and
partner pairing data, checklists, notes, memories and user documents.
INSTALL AS AN IN-PLACE UPDATE only. Never uninstall or clear data.

## Included since 0.1.418
- Content pushes in the recipient's language ("Kay sent you a hug"),
  using the name the recipient calls their partner.
- Plain Activity chat messages, trip messages and experience comments
  notify: at most one push per item per 10 minutes, "+N more".
- Meaningful partner changes push: new to-do / Activity / memory /
  reminder for you, moved dates, status changes, assigned to you,
  removed and restored. Minor edits stay silent.
- Quiet hours for partner-triggered pushes with one wake-up summary;
  no push for notifications already opened in the app.
- Tapping a push opens the exact item (Activity conversation, reminder
  with Done/Snooze, gesture pop-up, event, to-do, trip, occasion,
  experience, memory). Newer pushes replace older ones per item.
- Notification list shows the push wording and age; slider filter icon.
- Brand line "Two of us, One Space" under the OneSpace name in the top
  bar, splash and sign-in; removed from the Today body.

## Database and backend
- Applied live before this build (additive, non-destructive):
  0109 r48_notifications_2 (+ two small recorded follow-ups).
- Edge Function onespace-push-delivery v5 deployed (reads the new
  title/body/tag; older app versions still receive readable pushes).

## Verification
- "Verify OneSpace iteration" (analyze + tests) must succeed on the
  R48 branch before merge. This pipeline repeats analyze + tests,
  compiles, validates Firebase, package ID and signing certificate.

## Two-phone validation
Follow docs/R48_NOTIFICATIONS_QA.md (12 steps).

Controlled R48 signed preview candidate, November 15, 2026.
