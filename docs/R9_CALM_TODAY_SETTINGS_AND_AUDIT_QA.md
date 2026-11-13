# OneSpace R9 — Calm Today, central settings, accountable lifecycle

## What is delivered
- Today shows two synchronized partner columns: name and clock above the
  selected city, region, country, current temperature, conditions, high/low
  and probability of rain. No redundant clock date/city/offset/difference.
  Living together hides the entire clock/weather card.
- Removed the "Our space" heading and living-mode popup from Today.
  Relationship mode and visit dates live under Settings.
- Needs attention, Coming up together and Recent discussions are equal-rank
  collapsible accordions with matching typography, icons and count headings.
  Recent discussions remains accessible even with zero messages.
- Remember now focuses only on Calendar, To-dos and Notes. The upcoming
  date/due and recent note lists are no longer duplicated from Today.
- Settings is a dedicated header-gear destination separate from Profile.
  Relationship, preferred partner names, work/sleep schedule,
  scheduled-gesture consent, weather city, language and personal gesture
  management are reachable there. Preferences open context-specific editors.
- Gesture Sent/Received history includes localized date and local time.
- Activity actions: Mark completed, Cancel with optional reason, Reopen,
  Archive, Restore and Audit history. Archived Activities remain searchable
  in Coordinate > All; they are never hard-deleted.
- Component actions: Remove from Activity and Restore, with a "View removed
  items" control. Removal is soft and audit-backed.
- Database audit triggers now distinguish ordinary edits, Activity archive/
  restore, and component remove/restore with server timestamps and user.
  Existing prior revisions default to "edited" without deleting history.

## Device QA
1. On both phones, Today partner columns show the correct distinct city
   selections and each weather metric in the matching column.
2. Recheck living-together mode: no clocks or weather, and no empty heading.
   Return to living apart through Settings > Relationship.
3. Confirm three Today accordions share exactly one visual level and counters.
4. Open Remember; no duplicated dates, upcoming dues or recent notes.
5. In Settings, modify preferred labels, automatic consent, a city and
   relationship mode; confirm each persists after reopening.
6. Send gestures from phone A to B; view history on both and compare localized
   send time to phone clocks.
7. Complete an Activity, reopen it, cancel with a reason, archive and restore.
   Confirm all stage and archive events appear in audit history.
8. Remove a child component; verify it disappears from the active view,
   appears under View removed items, and can be restored. Verify old version
   and author remain in the audit trail.
9. Verify Android system-back gesture and double-back exit protection.
10. Repeat Calendar / To-dos / Notes opening and check performance on both
    Android phones. These are not considered device-verified yet.

## Continued iteration
- True device performance profiling, notification push delivery, work/sleep
  quiet hours and time-zone-aware alarms.
- Native Android share-in for links, images and flight details, with an
  Activity/list destination chooser.
- Press-and-hold / slide-to-cancel messenger-style voice UX polish.
- Shared Calendar source-of-truth integration, monthly/weekly/daily refinement,
  proactive gift-planning reminders and recurrence.
- Richer relationship memories, journeys and shared media experiences.
- Explicit mutual-deletion consent policies before allowing irreversible
  deletion of any shared object.

**No permanent deletion is implemented by the Archive/Remove actions.**
