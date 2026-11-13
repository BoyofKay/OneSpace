# R20 — OneSpace consolidated private Android test preview

Iteration: R18–R20 source strengthening with all R12–R17 functionality retained
Existing installed baseline: preview-0.1.397 (do not uninstall or clear app data)

## Release candidate
Source verified at 002712e86c7eeea974665d506ab8a5769fac39fd by https://github.com/BoyofKay/OneSpace/actions/runs/43521534804
- Committed dependency lockfile passed
- Flutter 3.50 analyzer passed
- Flutter automated tests passed, including Android Share intent regression
- Current test accounts, shared space, pairing and existing records were checked and preserved

## Included since the prior APK
- R18–R19: restored tagline and first-name greetings; local biometric/PIN unlock improvements; less aggressive inactivity locking; Today squares for A little love and Shared Experiences.
- Settings: Regional Holidays, weather unit preference (C/F), birthdays and important dates; Calendar and Notes archival access moved to History.
- To-do and Checklists: nested items with individual completion state, daily/weekly/monthly/yearly recurrence, list filters, red cancelled-list styling. Existing tasks remain as list containers.
- Notes: improved formatting actions, protected photo attachments, mention partner functionality.
- A little love: custom gesture shortcut restored, tile hints removed, new I miss you category and refreshed symbols.
- Daily Connection: two principal square actions, previous check-in records and requests preserved.
- Shared Experiences: media collection categories, direct Watch/Play/Open and mark-watched/rating actions, scoped history and easier archive/restore.
- Fixes: Activity like/dislike and Shared Experience review database permission-safe mutations; Contact edit history scoped to contact objects.
- R20 strengthening: remove redundant in-app 'Save a link or idea' menu entry while keeping Android external Share -> OneSpace; lazy checklist subscriptions and local day-boundary refresh; repair private-to-shared mention toggle; use offline first-name cache on saved sign-in; hide platform actions without a link; clarify share-receiver copy.
- All additive R19 schemas 0073–0076 were deployed, no destructive migrations. No R20 schema changes.

## Safety and publication gate
Trigger ONE signed optimized preview build. Keep package com.onespace.onespace.preview and original preview signing identity unchanged. Require Gradle build, analyzer and tests, APK signature and package verification, and retained artifact. Publish only the verified signed APK to GitHub Releases. Do not remove either test user's profile, saved data, keys, or relationships.

This is a PRIVATE TEST PREVIEW, not a public production launch. Both physical Android devices must be tested after in-place upgrade, particularly biometric unlock, save/share navigation, checklist recurrence, signed Notes photos, notifications, and activity ratings.

Trigger: R20 verified strengthening and consolidated R18–R20 Android preview, November 14, 2026.
