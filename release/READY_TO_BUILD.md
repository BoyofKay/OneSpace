# R33 — To-do and Checklists Crash Recovery (R32 included)

Require-Firebase-Config: true

Previous signed preview: 0.1.408.
Upgrade safely in place on both existing Android phones.
Do NOT uninstall, clear app data, reset the relationship, sign out, delete
old checklist records, regenerate signing keys or change Firebase config.

## What this build contains
- R33: fault-isolated To-do and Checklists loading; legacy task metadata
  handled without unchecked casts; migrated standalone tasks omitted from
  standalone list views; invalid rows never crash every checklist.
- R33: defensive rendering of checklist subitems and saved checkmarks.
- R33: null-safe auth handling for checklist entry, with recovery UI and
  no automatic account/session clearing.
- R33: explicit handling of malformed older records while retaining
  the existing task visibility fallback required by legacy tests.
- R32: quiet, opt-in check-in reply acknowledgments with server-verified
  sender-only permissions and realtime display. No new FCM event type.
- All R27–R31 prior features and Firebase two-way love-gesture delivery.

## Live backend evidence
- R33 inspection: 8 tasks total, 4 migrated legacy tasks (hidden as
  standalone), four visible list containers (including Old checklist),
  21 subitems and 3 completion records. No malformed row detected.
- Both partner accounts passed the RLS read regression:
  supabase/tests/0019_r33_two_phone_checklists_read_only.sql.
- NO TASK DATA OR CHECK HISTORY WAS DELETED.
- R32 new acknowledgment schema 0098 deployed with RLS; rollback test
  0018 passed and all test data rolled back.

## Verification gates already cleared
- R32 source validation GitHub Actions run 37 passed after test-only
  nullable fixture fix.
- R33 source validation GitHub Actions run 39 passed on commit
  523c24d6fbdee014b2b9dc25aeb64a43ea101a95.
- The first R33 test run caught a legacy shared-visibility mismatch
  which has been corrected and verified in the passing run 39.

## Mandatory build and QA gates
- Verify exact committed Flutter dependency lockfile, analyze and test.
- Compile a signed Android APK with the required Firebase config.
- Verify package com.onespace.onespace.preview and existing signing cert.
- Publish one new signed GitHub Release asset; confirm it exists.
- Device acceptance is NOT complete until the exact phone that crashes
  opens To-do and Checklists and expands Old checklist plus three newer
  lists, with no red error screen or forced closure.
- If a crash survives this defensive build, obtain Android Logcat/
  Flutter stack trace before making destructive database changes.
- Preserve user accounts, pairing, all public/private tasks and history.

Controlled recovery preview, November 14 2026.
