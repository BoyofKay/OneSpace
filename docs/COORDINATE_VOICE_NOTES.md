# OneSpace Coordinate — Private voice notes, R1

**Two of Us. One Space**

## User experience
- Inside an Activity use Add → **Voice note** to attach audio, including beneath an Option.
- In the Activity discussion, use the microphone beside the message composer to create a **voice comment** (including a reply to an earlier comment or a discussion tied to a component).
- Recording never starts automatically. Tap **Record**, grant explicit microphone permission when requested, then **Stop**.
- The draft can be **previewed**, replayed, **sent**, or explicitly **discarded**.
- Voice is capped at 120 seconds (2 minutes) and 5 MiB, mono AAC in an M4A file.
- On upload failure the sheet keeps the local recording for Retry or Discard. No silent posting; do not record in background.
- On success, the component/comment retains the original author, timestamp, parent reference and activity association.
- Compact **play/pause** button and duration appear within the relevant component or message. Playback uses a short-lived (120-second) private signed URL.

## Storage/security
- New bucket `onespace-activity-voice` is private. Allowed content type is audio/mp4 (plus audio/x-m4a compatibility).
- File path: `activityUUID/userUUID/randomUUID.m4a`; only authenticated contributors can upload to their own folder when authorized for the Activity.
- Audio playback reads require the same Activity visibility rules enforced by RLS; no public bucket or permanent public URL.
- Unreferenced failed uploads may be cleaned up by their own uploader. Published audio referenced by a component or comment cannot be deleted by that cleanup policy.
- `activity_comments.voice_path` and `voice_seconds` are nullable, additive fields. Existing text comments are unchanged. Voice comments retain a non-empty descriptive `body` for compatibility.
- Recording files are temporary and cleared on explicit Discard or successful Send; no automatic transcription.

## Acceptance tests before production
- Android permission grant/deny and permanent-deny handling; recording start/stop and background interruption.
- Preview, retry on network interruption, and successful Send in both component and comment contexts.
- Cross-account playback from the authorized partner and denial for unrelated accounts.
- Correct reply/option association, replay after signed URL expiry, audio focus with calls, restart/rotation handling.
- Flutter analyzer/tests, Android APK build and preview signing checks must pass.
