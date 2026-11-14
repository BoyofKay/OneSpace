# R36 — Thoughtful Personal Love Reminders

Require-Firebase-Config: true

Previous preview release build: 0.1.411 (Occasion preparation).
Keep the existing Android package com.onespace.onespace.preview,
preview signing certificate, two accounts, pairing, Firebase config,
biometric unlock and all user data. Never uninstall or clear storage.

## Included features
- A Little Love offers a one-tap entry to create an optional, personal
  reminder to send a thoughtful gesture. Nothing is sent automatically.
- Suggest exact local 9 AM, 6 PM or 9 PM, with editable custom time.
  No assumption about actual working hours or partner time zone.
- Choose a gesture category or Any gesture, and show creator's own
  last-sent history as a gentle optional reference.
- Reminder uses existing backend/FCM due delivery to creator only.
  Opening reminder leads to A Little Love; sender manually chooses and
  sends a gesture in the normal way. Partner sees nothing until then.
- Private only, audience me. Existing automatic-ritual configuration
  remains unchanged while user considers replacement.
- All previous R34 checklist recovery and R35 Occasion reminders remain
  included unchanged.

## Security and verification
- Additive migration 0100 deployed to the same Supabase project, using
  nullable intent fields and a private-only database constraint.
- RLS rollback-only SQL test 0021 PASS: cannot expose personal prompt to
  partner, cannot forge a shared audience and cannot insert exact duplicate.
- R36 source verification run 45 PASS for logic, UI and full test suite.
- Final copy-label verification run 46 checks final source; this signed
  preview pipeline independently repeats locked dependencies, analyzer
  and full Flutter test suite before building.
- Two-phone acceptance: docs/R36_THOUGHTFUL_LOVE_SELF_REMINDERS_QA.md.

## Signed release gates
- Build only after full Flutter analyzer and test success.
- Verify Firebase Android config and unchanged signing certificate.
- Verify Android package ID and publish a single APK.
- No physical-device acceptance is claimed until the two installed
  phones test gesture reminder privacy and manual send flow.

Controlled preview candidate November 14 2026,
source commit f31344ae89a0c50a62869ac29e1805ad970fce5b.
