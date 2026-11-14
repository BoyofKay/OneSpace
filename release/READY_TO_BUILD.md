# R22 — First-class Reminders, single Sign-In, and connected checklist UX

Preview baseline: **0.1.399**. Upgrade over existing installation; do NOT uninstall, clear local storage, or recreate accounts. This is a controlled two-partner Android test preview.

## Candidate scope
- **Remember → Reminders:** personal/shared reminders, configurable recipient(s), due date/time, notes, linked checklist/Calendar/Occasion, archived history, Done and Needs Follow-up with outcome notes, Today/Tomorrow/Custom snooze, each partner's outcome and history.
- Database migrations 0080–0083: RLS reminders/recipient states/action audit, privileged response RPC with explicit actor membership checks, every-five-minute in-app notification dispatcher, existing notification constraint compatibility, server-side linked-object privacy validation, and corrected Home/Remember counts excluding migrated standalone tasks.
- New reminder deep links in the in-app Notifications center; global Search finds reminders. Stream watchers sync partner status/snooze changes while Reminders screen is open.
- Auth: **one screen** for signed out or session locked; same email/password/fingerprint layout. Fingerprint/device PIN unlocks an already-valid saved session. True sign-out requires server authentication (including native OS password manager autofill when available), no stored substitute password.
- To-do and Checklists: named checklists with nested items, clearer "Both of us" assignment; shared editing separated from per-person checkbox responsibility. Old checklist and its four migrated subtasks retained.
- Permanently retired old standalone Lists Flutter source files and tests, after earlier R21 retirement of empty tables and Today link. Notes validation tests retained.
- R21 camera-first Memories and Android contact import/export maintained.

## SQL regression evidence
- R22 privacy and actions regression test 0010 passed under rollback, including partner-only outcomes, follow-up history, snooze and idempotent cron re-dispatch.
- Existing R21 checklist and Memory privacy tests passed before this iteration.
- Existing accounts, device sign-in material, shared space, messages and live records remain untouched by synthetic tests.

## Known limits / future work
- Every-five-minute backend scheduler delivers **in-app notifications**, not native background push. Firebase Cloud Messaging requires project configuration and device credential setup. The scheduled check can be up to five minutes after due plus delivery latency.
- This release includes **one-time** reminders, not recurring Reminder schedules or self-love nudge logic.
- Native OS biometric/PIN cancellation, Samsung Pass, two-device notifications and shared update UI need physical acceptance testing.
- Advanced checklist recurrence weekdays/timezone/holiday exceptions, Flutter Quill Notes 2.0, Occasion shopping planner, Trip documents and Scrapbook Studio not yet implemented.
- A valid session is never recreated from biometric verification alone after true sign-out.

## Publication gates
One reproducible signed preview APK, gated on Flutter 3.50 dependency lock validation, analysis, all Dart tests, Android Gradle/Kotlin compilation, same preview signature, same package com.onespace.onespace.preview, and retained workflow artifact. Publish only if verification succeeds. Do not change production signing identity or reset any user data.

Trigger: R22 integrated preview, November 14, 2026.
