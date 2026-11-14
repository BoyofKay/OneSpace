# R29 — Shared Experiences live collaboration and scheduling acceptance

**Scope:** Source-only changes after R28 and R27; no new table, secret, migration,
account reset, automatic purchase or additional phone permissions.

## Built
- Subscribes to realtime changes of shared experiences in the current paired space,
  with 650 ms debounced refresh, stale-response guards, and channel cleanup.
- On the experience detail screen, subscribes to the selected experience, comments
  and partner reviews; refreshes after 550 ms and cleans up on navigation.
- Preserves locally drafted reviews and comments when partner activity arrives.
  A new review is saved only when the author explicitly taps Save.
- Prevents stale edits of experience metadata, one-tap completion, archive, and
  date planning using the `updated_at` version already maintained by the database.
  Conflicts refresh the current record and give actionable feedback.
- "Plan together" now selects a calendar date and immediately saves status
  `planned` and `planned_on`, instead of merely opening an uninitialized editor.
  This is an existing record update (no duplicate event creation).
- Existing manual ExperienceEditor supports status, planned date and completion date,
  and saves dates as local calendar dates rather than converting time zones.
- Experience cards show current progress and relevant dates.
- Quick completion and review support all six categories, with *watched*, *listened*,
  *read*, *played*, and *enjoyed* wording as appropriate.
- Preserves existing R13 server-side new-suggestion/comment notifications, and
  R25 native FCM delivery; no additional background push type was added.

## Quality gates
- Unit tests for filtered shortlist, per-category labels, date-only formatting,
  and deterministic cross-time-zone suggestions.
- Run committed dependency resolution, `flutter analyze`, and `flutter test`.
- Android signed preview release only after green verification.
- Keep preview package `com.onespace.onespace.preview`, certificate, accounts,
  paired space, app state, and existing Firebase configuration unchanged.
- Do not clear data, uninstall either phone, or expose private objects.

## Two-phone QA after a verified APK
1. Keep the existing logins and pairing. Leave both phones on Shared Experiences.
2. Create an experience on A. B should see it without pulling to refresh.
3. On B, schedule a date through **Plan**. A should see Planned and the same
   calendar date, even when the devices have different time zones.
4. In Today, confirm the planned experience appears under Coming Up Together
   if its date is in the next seven days, and opens the original experience.
5. Open the same experience on both devices. Type an *unsent* review on A.
   On B, add a comment; A should see the comment without losing its draft.
6. Save a review on A; B should see it. Each partner edits only their own review.
7. Both partners open the editor for the same experience. A saves first;
   B attempts a stale save. B must receive a conflict warning, not overwrite A.
8. Complete a movie/show, book, music title, game, and miscellaneous item.
   Confirm correct wording, completion date, and the rating prompt.
9. Archive on A and restore on B; the change should refresh on both devices.
10. Test deep link from a suggestion/comment notification with a valid older item.
11. Confirm R25 push delivery, To-do/Checklists, Notes, Trips, and Scrapbooks
    still function; verify no new permissions or account changes.

## Not claimed
- Realtime transport can be interrupted by network or OS restrictions. Pull to
  refresh remains available; permanent offline event queue is not implemented.
- Existing push notices for *new suggestions and comments* are retained.
  Planning changes do not yet generate a distinct scheduled-notification type.
- These steps are not marked phone-tested until both devices are actually checked.
