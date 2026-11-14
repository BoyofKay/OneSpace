# R37 — Listen to Checklists (native voice readout)

Require-Firebase-Config: true

Previous signed preview pipeline: 0.1.412.
Preserve the exact existing package com.onespace.onespace.preview,
trusted signing key, Firebase Android config, pairing, biometrics and
all private/shared checklist data. Install only as an in-place update.

## Scope
- Expanded checklist now contains Listen to checklist.
- Read remaining unchecked or all active subitems, read an individual
  step, previous/next/repeat and adjustable speech speed.
- Uses only the signed-in partner's authorized checklist and their own
  current-cycle completion flags. No data writes, automatic completion,
  remote recording or microphone permission.
- Native Android TextToSpeech service, including Android 11+ TTS_SERVICE
  manifest visibility. Native Kotlin splits long scripts into small
  queued utterances and stops when application backgrounds/destroys.
- Native iOS AVSpeechSynthesizer integration for future iPhone trial;
  iOS compile and device QA remain separate from Android APK gate.
- Speech can use online TTS services if the installed phone voice
  engine requires it; no OneSpace backend voice upload is performed.
- Existing checklist ExpansionTile remains on safe ValueKey and nested
  TextField scroll offset remains disabled (R34 crash prevention).
- All R35 occasion prep and R36 personal love reminder features remain
  included, with no database changes for R37.

## Evidence and mandatory gates
- R37 source last commit 9b40a553ac47ea044548a586f04c886009623b57.
- Source verification GitHub Actions run 49 checks corrected imports and
  test fixture; APK must independently rerun the entire locked Flutter
  dependency analyzer/test gate and refuse to publish if tests fail.
- Android Gradle Kotlin compilation is required and must succeed before
  the APK is signed, uploaded and released.
- No new Supabase migration, FCM secrets, service accounts, or user data
  manipulation. Keep release marker isolated from R36/411/412 commits.
- Check docs/R37_VOICE_CHECKLIST_READOUT_QA.md for full two-device
  acceptance and privacy scenarios.
- A passing CI is not a phone-tested claim. Android TTS availability,
  audio quality, lifecycle stop and checklist expand/read actions must
  be verified on the existing phones.

November 14 2026; controlled signed candidate R37.
