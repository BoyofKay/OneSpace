# Coordinate — Chat identities and voice-note UX

**One Life. Two Places. One Space.**

- Show **You** for the current user's messages. The avatar displays the initials of the user's own saved profile name. The other partner's messages show their saved full display name and initials. Unknown identities use safe fallbacks, not raw user IDs.
- Chat microphone tap is the user's explicit recording gesture, so recording starts as the voice panel opens. No extra "Record" tap. This works for both conversation voice comments and Activity/Option voice components.
- Compact controls: elapsed recording time, Stop, optional Preview, Send, and clear Cancel/Discard. Permission denial leads to a retry action; stopping when the app leaves the foreground remains mandatory. No recording is automatically sent.
- The recorder indicates reply or component context, preserving it in the posted contribution.
- Audio notes use a single-line player: Play/Pause, seek slider, remaining duration. No redundant component-type header or large empty card. Player fetches a private short-lived signed link on demand.
- Voice component title and caption can be edited without replacing, overwriting or republishing the existing audio file. Editing goes through the existing component revision history.
- Voice bubbles no longer interpret a playback tap as "Reply"; long-press exposes the Reply action. Text bubbles retain tap-to-reply. Copy-message applies only to text messages.
- All earlier Activity components, messages, edit histories, sharing and private storage continue to work.

Acceptance on physical phones: permission grant/deny, recording auto-start only after microphone tap, foreground interruption, stop/preview/send/cancel, storage cleanup, voice reply context, pause/seek, option-linked audio, two-partner playback, avatar initials, long names, RTL and narrow screens.
