# R5 — OneSpace relationship UX and shared tags

## Delivered in source
- Gesture history moved to the top-right history action, with Received and Sent filters.
- Gesture notifications display a type-specific themed dialog, not the gesture tab.
- Seven colored default gesture cards and creator-owned custom gestures.
- Custom gestures allow an optional ritual trigger; automatic delivery still requires an enabled ritual schedule and recipient consent.
- Recipient-facing auto-generated gestures remain transparently labeled.
- Profile supports multiple preferred partner labels; Today chooses one for the current session.
- Activity tag editor looks up a shared saved-tag inventory, allows creating tags, and global search can open matching Activities.
- Today feature grid uses real modules and a state-specific relationship icon.
- Activity chat bubbles show initials, offer inline @ suggestions, and place the composer inside the resizeable body.
- A compact voice recording workflow preserves Stop, Preview, Send and Discard.
- Fatal widget build failures display a copyable diagnostic instead of Flutter's red-on-black surface.

## QA priority
Verify the APK before replacing an existing installed release. On two physical phones, test the gesture popup and history, RLS visibility, custom manual and scheduled gestures, keyboard positioning and voice attachments, @ matching including email addresses, tag creation/search, and the previously reported Calendar/To-dos/Notes red screens. Runtime issues cannot be declared fixed until reproduced and tested with phone logs.

## Current boundaries
The red-screen root cause is still unknown without a device exception. Flutter ErrorWidget diagnostic is a recovery/reporting path, not a root-cause fix. Push notification delivery, complete calendar syncing, multi-step voice press-and-hold interaction, and thorough dark/RTL polish are subsequent work.
