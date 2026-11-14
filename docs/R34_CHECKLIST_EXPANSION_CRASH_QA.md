# R34 — Expanding a checklist still fails in Release 409

## Report and scope
The user tested a published signed preview and reports **every** checklist
fails on tap to expand, including newly created checklists. R33 guarded
model conversion, but this demonstrates R33 did not solve the UI blocker.

## Evidence
- Existing paired live space: one Old checklist plus three newer lists.
- Four migrated historical standalone tasks, 21 subitems, three checkmarks.
- Only **one** of the four migrated items contains legacy_target_date; the
  target-date field does **not** participate in TaskChecklistPanel expansion.
- Current visible checklist rows use `recurrence = 'none'` and normal
  recurrence JSON. Supabase RLS read tests for both members passed R33.
- Both checklist data tables are in the Supabase realtime publication.
- Widget tests reproduced the crash: Flutter's ScrollPosition.restoreScrollOffset
  reads an ExpansionTile/PageStorage bool as double? when the nested
  EditableText in the subtask input is created. This is a shared UI-state
  key conflict, independent of database contents.
- A physical-device stack trace is still unavailable; phone acceptance
  remains required.
- Avoid deleting legacy records or clearing application data without proof.

## Changes under test
- Checklist expansion stream construction is surrounded by exception
  handling, so failure to initialize a realtime subscription cannot
  propagate out of the expansion callback.
- Replaced the checklist ExpansionTile's PageStorageKey with ValueKey
  (its expanded state is already retained in _expandedLists) and set the
  nested TextField scroll controller to keepScrollOffset:false so it never
  tries to read the ExpansionTile's stored bool as a scroll double.
- The widget regression intentionally retains an old PageStorageKey parent
  and verifies nested input rendering does not throw.
- Subscription to checkmarks now uses one parent-task realtime filter,
  and the current recurrence cycle is selected from the stream in memory.
  This reduces cross-filter complexity in widget initialization. Existing
  RLS, per-person filtering and latest 500-row cap remain.
- Add explicit widget tests with the actual collapsed-to-expanded tap
  transition on both new items and old migrated items with a target date.
- Assert a checkmark from another user or another cycle is not displayed.
- Assert network transport errors leave a readable, recoverable view.

## Important limitations
- Automated tests and RLS checks do not prove physical-device behavior.
  The existing app has `OneSpaceErrorFallback`, which presents a
  **Copy error details** control for Flutter build exceptions. If
  expansion still fails, request its exact copied error text, or capture
  `adb logcat` around the tap if the app force-closes.
- The goal is to diagnose the shared expansion path. Do not delete or
  modify actual checklist rows, and do not call the feature fixed before
  both phones can expand and toggle checkmarks.

## Two-phone acceptance
1. Upgrade signed preview in place; don't uninstall/clear data.
2. On both phones, open To-do and Checklists.
3. Expand each of the four lists; never see the error fallback or a
   forced closure. Collapse/reopen and navigate away/back.
4. Check Old checklist, including migrated subitem with date metadata.
5. Add subtask, save, and verify remote sync. Check and uncheck;
   other partner must maintain independent cycle state.
6. Verify Check-in, Firebase love gestures, plans, partner picks and
   biometrics remain functional.
7. If any expansion fails, capture precise diagnostic text before any
   further destructive action.
