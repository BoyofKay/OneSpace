# Coordinate R2 — Compact Activity Interaction

OneSpace · One Life, Two Places

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

## Deferred
- Voice note recording/playback requires permission management, private media storage and expiring authenticated URLs. Do not show a nonfunctional mic button.
- Images/screenshots need the same private storage rules and view-only grants.
- Native Android share-in and searchable comparison data are follow-on milestones.
- A more advanced comparison should compare structured fields row-by-row and preserve per-partner choices.

## Acceptance
- One-line toolbar doesn't wrap on 360dp phones.
- Activity title appears in app bar and not duplicated in body.
- Notes display multiline detail without truncation.
- Step tapping toggles status; links and map locations open their respective apps.
- Each reaction is independently recorded per partner; menu labels make the action discoverable.
- Replies preserve chronological order, timestamps and references.
- All existing Activity rows and old JSON component values still render.
- Two-account physical-device verification required before production release.
