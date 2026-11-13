# R11 — Ready for one final candidate

Iteration: R11 — Personal actionable Needs Attention
Previous confirmed preview: 0.1.394

Release scope:
- User-specific action queue with overdue, due-today, directly requested,
  tomorrow and urgent/high-priority ranking.
- Grouping by Activity so related reminders and mentions do not duplicate it.
- Personal snooze with source-level RLS, without modifying shared data.
- Deep links for Activity, To-do and pending partner check-in reply.
- Opened Activity mentions/replies acknowledged for that viewer.
- Show all actions, not a single seventh-item shortcut.
- Updated CI: source commits never start APK builds and cannot cancel a
  final build; lockfile is not pushed from the CI runner.

QA gates: Flutter analysis, automated tests, preview APK signing/package
verification, workflow artifact, GitHub Release asset verification.
Two-device acceptance remains required after APK publication.

This file must be changed only once for the completed iteration.
