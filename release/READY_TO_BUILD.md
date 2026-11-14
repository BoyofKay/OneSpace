# R34 — Reproduced To-do and Checklists Expansion Crash Fix

Require-Firebase-Config: true

Previous published preview: 0.1.409.
Install over the existing app on both phones. Do not uninstall, clear
storage, reset the paired space, delete any checklist data, or change
the Firebase configuration, package ID or signing certificate.

## Reproduced issue and remedy
- User reports both older and newly created checklists fail on expanding.
- Flutter tap-to-expand widget tests reproduced a _TypeError:
  a bool saved by ExpansionTile under PageStorageKey was read by
  nested EditableText/ScrollPosition as a double scroll offset.
- Replaced the ExpansionTile PageStorageKey with ValueKey; existing
  in-memory _expandedLists retains each list's expanded state.
- Explicitly configured the nested subtask TextField to use a
  ScrollController(keepScrollOffset:false), with correct disposal.
- Simplified checklist checkmark realtime subscription to one task_id
  filter, selecting current recurrence cycle per user in memory.
- Added recoverable stream initialization handling and widget regression
  tests that cover the collapsed-to-expanded tap transition, including
  an Old checklist entry with legacy target date and the original
  PageStorageKey ancestor collision.

## No data destruction
- Exactly one of four migrated legacy subtasks has legacy target_date.
  This is not used in the expansion code and is not the crash cause.
- Live database data and all four visible lists are retained.
- Existing partner permissions, independent checkmark history,
  pairing, biometric unlock, notifications and FCM delivery unchanged.

## Quality gates
- GitHub verification run 40: SUCCESS, initial isolated expansion test.
- GitHub run 41: failed exactly in new expansion tests with reproduced
  bool/double scroll state issue; root cause now addressed.
- This signed Android release must rerun Flutter locked dependencies,
  analyzer and entire test suite including the reproducer. If any test
  fails, compilation/publication is blocked by workflow dependency.
- Verify unchanged signed preview ID com.onespace.onespace.preview and
  existing certificate before publishing one APK asset.
- Physical-device success is NOT claimed until the affected phone
  expands Old checklist and all three other checklists without error.

## If any error persists
OneSpace now includes a fuller Copy error details stack trace. Copy
that error from the affected phone before making any database cleanup
change. Never delete other users' current lists to test a guess.

Controlled Android preview source commit
9fd2fc65e9f4ede52796fecbd4416faa8a9161e4, November 14 2026.
