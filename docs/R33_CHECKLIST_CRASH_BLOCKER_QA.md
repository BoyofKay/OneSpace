# R33 — To-do and Checklists crash blocker

## Incident
User reports the module still crashes when opened on Android, including
after previously published Release 407. User offered permission to remove
old checklist data *if the old data is the cause*.

## Live database investigation (2026-11-14)
- One paired space, two members.
- 8 task records: 4 historical standalone records already migrated and
  hidden, 1 **Old checklist** container, 3 newer active containers.
- 21 checklist child rows (4 linked to migrated legacy tasks) and 3 per-user
  completion records.
- No null recurrence/rule/title/creator, no non-object recurrence rules,
  unexpected priority/status values, or empty active checklists.
- Both the four migrated records and the new lists have normal column types.
- No evidence presently implicates old data. **No records deleted, archived,
  reassigned, reset or otherwise mutated in this iteration.**

## Source hardening
- Task parsing tolerates old optional/string field formats instead of
  using unchecked casts, with conservative visibility fallback.
- List boundary ignores migrated rows and isolates invalid records.
- An invalid task or checklist child will show a recoverable warning
  without taking down the entire list.
- Sign-in/session gaps do not dereference a null currentUser.
- Checklist check records require a matching item/user and boolean
  completion value before being rendered.
- All server-side RLS, existing row IDs, check history, assignment,
  recurrence, per-user completion and archived history remain unchanged.
- Added pure regression tests for migrated legacy records, malformed rows,
  null fields, and valid current checklists.

## What is not claimed
An Android exception stack trace from the affected phone is not yet
available, so the underlying native/Flutter crash is not proven.
The hardening reduces plausible rendering failure points but must be
validated with a signed installable APK and the *same account/data*
on both Android phones. Do not equate unit test passing with a confirmed
physical-device crash fix.

## Acceptance after next signed APK
1. Upgrade **in place** over existing APK; do not uninstall or clear data.
2. From Today, tap To-do and Checklists. It must open promptly.
3. Open **Old checklist**, then each of the three newer checklists.
4. Add and remove a subtask; mark complete and incomplete on both phones.
5. Verify each user's per-cycle checkmarks stay independent.
6. Test a recurring checklist and day change without reset of history.
7. Test archive/restore, task status actions, priority/assignment,
   and private versus shared visibility.
8. Verify FCM gestures remain delivered on both phones.
9. If the app still crashes, collect Android Logcat around the precise
   tap for a full stack trace; do not blindly delete all task data.

## Destructive-data policy
Only if future evidence isolates a specific problematic legacy record:
first export a restorable copy of its task, child and completion records;
then explicitly verify references and remove only the implicated old
record(s) in a transaction. Do not delete newer checklists or unrelated
tasks without cause.
