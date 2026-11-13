# OneSpace Coordinate — Private photo / screenshot attachments

This feature is additive. Existing Activities, conversations and pairings remain intact.

- Choose **Add → Photo / screenshot** in any Activity, or attach a photo beneath a specific Option.
- Android invokes the system gallery picker. The user selects a specific image; there is no broad gallery scanning or device-location access.
- Validate the actual image signature for JPEG, PNG, WebP and enforce a maximum size of 6 MiB. Gallery selection may compress images down to 1600px / 82 quality where supported.
- Upload to a private Supabase bucket named `onespace-activity-media`. The path is `activity-uuid/user-uuid/file-uuid.ext` and is never a public URL.
- Upload and signed URL creation require an authenticated, RLS-visible Activity. Only the contributing user can upload to their own folder.
- Existing photo records use the `image` reusable Coordinate component. Selecting a photo creates an attributed component within the Activity; screenshots are not free-floating notes.
- The Activity viewer obtains a fresh short-lived signed URL (120 seconds). Tapping the thumbnail opens a larger view with zoom.
- Upload failure before component creation attempts cleanup. Storage DELETE policy only permits cleanup by the uploader if no component already references the asset; existing published photos cannot be silently erased.
- Component revisions preserve edits to photo captions. Media itself is not overwritten in place.
- No public bucket, no service role in the app, no background capture.

**Not yet verified on physical Android devices:** actual photo selection, HEIC conversion, file picker cancellation, mid-upload network loss, multi-account photo viewing, and offline behavior. Those tests must run before treating this as production-ready.

**Next phase:** Secure audio voice messages will use the same parent-specific permissions and private-media design, with microphone consent, record/preview/discard, and authenticated playback.
