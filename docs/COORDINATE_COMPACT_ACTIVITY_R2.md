# Coordinate R2 — Compact Activity Interaction

OneSpace · One Life. Two Places. One Space.

## Layout (implemented)
- App bar displays the Activity title with an edit pencil; no duplicate 36px heading.
- One metadata action strip: Priority, Status, Due date, Add component, History; all icon buttons with tooltips and accessible labels. A single subdued metadata summary remains visible.
- Activity details appear as readable body text without a large container. Tap body/edit pencil to revise; previous revisions are preserved.
- Components show the information first. Type is indicated through a 19px icon, not a text prefix. Notes and specifications are shown in full, not truncated into one subtitle line.
- The only permanent action on an item is a compact overflow menu. Tap opens a URL, opens Maps, toggles a Step, or opens contextual actions depending on item type. Long-press exposes discuss, like/dislike, edit, attach subcomponent, and history.
- Reactions display only when present, in text-size notation rather than full-height Like/Dislike controls.
- Compare appears when at least two Option components are present. Price, currency, specifications, source, and notes can be captured on each Option.
- Conversation shows message bubbles, author initials and original date/time. Tap a bubble to reply, long-press to copy/reply. Composer stays at bottom.
- Comments may attach to a component; reply threading is preserved.

## Component behavior
- URL links: validate HTTP(S) URL and open default external browser.
- Locations: store a place/address (not live GPS), open Google Maps search externally. No location permission necessary.
- Options: named candidates with link, observed price/currency, specifications, notes and compare sheet.
- Prices: numeric observed amount + ISO currency; price is not automatically refreshed.
- Steps: completion toggle; existing history and author ID remain protected by database permissions.
- Dates/reminders: a date picker, with an explicit warning that push notifications are not yet active.
- Notes/specifications: free-form readable text with type-aware editor.
- Tags: short labels attached to Activity or Option.
- Mentions: existing data type remains compatible; actual notification dispatch is not available.

## Voice notes — interaction and security specification (next implementation slice)
Voice is a first-class contribution that can be attached either to an Activity/Option as a component or sent in the Conversation as a comment. It must have the *same author, original timestamp, contextual reply association and RLS access control* as text contributions.
1. The composer mic opens a record interface: **Record → Stop → Preview → Send or Discard**. A mic in the Add-item sheet creates a standalone attached voice component.
2. Keep voice UI compact: play/pause button, duration, sender initials and timestamp. No autoplay and no large waveform-only card. Long press allows replying and viewing details.
3. Record only when the user taps Record and grants device microphone permission. No background capture.
4. Store the recording in a **private Supabase Storage bucket**, validate content type/size, and use authenticated, short-lived signed playback URLs; do not put public permanent audio links in database rows.
5. Preserve the file on a failed upload for user-controlled retry, without silently posting a comment or losing the draft. Explicitly clean up discarded local files and incomplete uploads.
6. No automatic transcription or third-party voice processing without clear user opt-in.
**Not shipped in R2**: do not display an inert microphone control. Voice needs a secured media implementation and Android device recording/playback tests before release.

## Deferred
- Images/screenshots need the same private storage rules and view-only grants.
- Native Android share-in and searchable comparison data are follow-on milestones.
- A more advanced comparison should compare structured fields row-by-row and preserve per-partner choices.
- The next R2 refinement groups Options with their child prices/specs, Steps, and Notes & References separately so a component's context is visible at a glance.

## Acceptance
- One-line toolbar doesn't wrap on 360dp phones.
- Activity title appears in app bar and not duplicated in body.
- Notes display multiline detail without truncation.
- Step tapping toggles status; links and map locations open their respective apps.
- Each reaction is independently recorded per partner; menu labels make the action discoverable.
- Replies preserve chronological order, timestamps and references.
- All existing Activity rows and old JSON component values still render.
- Two-account physical-device verification required before production release.
