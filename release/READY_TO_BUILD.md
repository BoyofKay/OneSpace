# R46 + R47 — Baseline hygiene and Reminders for real life

Require-Firebase-Config: true

Previous signed preview: 0.1.417 (R43/R44 era source).
Preserve the existing com.onespace.onespace.preview Android package,
same signing certificate, Firebase config, biometrics, all account and
partner pairing data, checklists, notes, memories and user documents.
INSTALL AS AN IN-PLACE UPDATE only. Never uninstall or clear data.

## Included since 0.1.417
- R44 expanded action history and R45 editable/retractable Experience
  comments (already merged, never shipped in an APK).
- R46: automatic love gestures retired; Shared Goals removed from the
  app (data kept); tagline "As a couple, we have One Space"; stale copy
  removed; Troubleshooting link; Today/Yesterday meeting labels.
- R47: repeating reminders (daily, weekdays, weekly on days, monthly,
  yearly, every N, up to 6 times a day, end date), Done for this time,
  Missed occurrences, quiet hours for partner reminders, Urgent, linked
  item closed stops alerts, partner local-time hint, reminders in Today
  Needs attention and Coming up.

## Database
- Applied live before this build (additive, non-destructive):
  0107 r46_retire_automatic_gestures; 0108 R47 reminders (three
  recorded migrations). Older app versions keep working.

## Verification
- "Verify OneSpace iteration" (analyze + tests) must succeed on the
  R47 branch before merge. This pipeline repeats analyze + tests,
  compiles, validates Firebase, package ID and signing certificate.

## Two-phone validation
Follow docs/R46_BASELINE_HYGIENE_QA.md (11 steps) and
docs/R47_REMINDERS_FOR_REAL_LIFE_QA.md (11 steps).

Controlled R46+R47 signed preview candidate, November 15, 2026.
