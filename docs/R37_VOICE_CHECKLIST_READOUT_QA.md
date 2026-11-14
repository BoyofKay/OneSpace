# R37 — Listen to checklists (voice readout)

## Purpose
Make a daily or recurring checklist useful while someone is getting ready,
carrying a baby, or has their hands occupied. This is a *read-only*
accessibility workflow, not a microphone-driven assistant. Users still
check off items themselves, as agreed for independent partner completion.

## Scope committed
- An accessible **Listen to checklist** control inside expanded checklists.
- Listen to remaining unchecked items (default) or all active subitems.
- Read all selected subitems in list order, one step, or navigate
  previous/next and replay an individual step.
- Change speech speed (0.75× / 1.0× / 1.25×). Spoken language follows
  the current app locale if supported by the device engine, otherwise
  the phone speech default.
- Speech uses the Android TextToSpeech service or iOS
  AVSpeechSynthesizer over the same first-party MethodChannel.
  No dependency/download, no extra permission, no cloud function.
- Text is read only on explicit user action. The phone's installed
  voice engine *may* use online synthesis depending on its settings.
- Playback stops when the app is backgrounded/locked, the sheet closes,
  or the user taps Stop. Microphone access is never requested here.
- The feature does not automatically mark any task complete, resend
  notifications, change settings, or add data to the backend.
- Existing R34 ExpansionTile PageStorage collision fix stays intact.

## Safety and privacy
- Uses only the RLS-filtered subitem rows already loaded for the
  expanded checklist, and only current-user/current-cycle completion
  state. Does not read any partner's private data.
- Archived/malformed items excluded, scripts sanitized of control
  characters, names capped at 240 characters and readouts capped at
  200 lines. Android splits long utterances to stay below the TTS
  engine's per-utterance limit.
- Native speech stops on Android onPause/onDestroy and iOS resign-active.
- No server migration is required.

## Tests
- Pure Dart script tests for item order, old invalid rows, completed
  filtering, empty scripts and item caps.
- Flutter widget tests mock only the platform bridge and verify
  remaining-vs-all selection, native invocation, step navigation,
  and stopping when the sheet unmounts.
- Full Flutter analyze/test required before signed APK. Android
  release pipeline must compile Kotlin too. iOS native code requires
  a subsequent macOS/iOS compile and real-device verification.

## Two-phone acceptance
1. Install next signed APK over the last working preview, not fresh.
2. Open To-do and Checklists on both devices and expand the old
   and a newer checklist—verify the R34 crash stays resolved.
3. Tap the speaker icon and choose **Still to do**. Completed items
   on this account must not be read; the other account's own
   progress is independent.
4. Read all, read one, switch between steps, adjust speed and Stop.
5. Try a shared checklist, private checklist and recurring instance.
6. Background/lock the phone while reading: speech must stop.
7. Test with airplane mode using an installed offline voice
   and test a phone lacking a compatible engine (recoverable error).
8. Check no item is marked complete by speech and nothing is
   sent to the other partner or Firebase.
9. Recheck normal checklist editing and calendar/gesture pushes.

## Out of scope
- Hotword activation, always-on microphone, automatic voice commands,
  wake-word assistant, hands-free checkmark changes, and continuous
  playback while the app is locked. Those need a separate product
  and security review.
