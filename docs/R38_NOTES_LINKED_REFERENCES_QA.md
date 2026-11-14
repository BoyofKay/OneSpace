# R38 — Notes 2.0 linked source objects and privacy

## Outcome
A saved rich-text note can reference a real OneSpace object without
duplicating its data or changing the underlying object:
- To-do and Checklists
- Calendar event
- Occasion or surprise
- Shared Experience

The References section in the Quill editor supports selecting an
existing accessible item, displaying its latest live title, opening
its original screen, and unlinking it without deleting the original.

## User workflow
1. Remember > Notes > open a saved note. New notes must be saved first.
2. Select **Link item**, choose object type, select an accessible item.
3. The link appears below the note. Tap its title to open the actual object.
4. Unlink removes only the reference, never the task/event/occasion/experience.
5. Archived/read-only notes keep their references visible but non-editable.

## Data and authorization
- Migration 0101 introduces `public.note_references` and
  `private.note_reference_visible`, which verifies note and target
  membership, matching space, and both objects' RLS.
- Migration 0102 prevents a view-only private-note recipient from
  changing its references.
- No link title or private body copied into the reference table.
- A shared note can link only a shared task/event/occasion, never a
  private surprise. A private note may link an authorized private object.
- Both users see references in shared notes, but an inaccessible
  target is not resolved or displayed.
- Live source titles are fetched only through each original table's
  RLS. The reader gets no cached private title when access is revoked.
- Duplicate links are rejected by a unique constraint.
- Existing notes, rich-text deltas, attachments, archived states,
  two-phone pairing, Firebase configuration and checklist data untouched.
- The new table uses SELECT/INSERT/DELETE only, with RLS; it grants
  no UPDATE and no bulk modification of source objects.

## Verification
- Rollback-only SQL test 0022 passed after migrations 0101 and 0102:
  two accounts, private note hidden, shared note reference visible,
  private surprise cannot enter a shared note, invalid target rejected,
  duplicate rejected, and unlink preserves the source.
- Flutter note_reference_rules unit tests cover allowed object kinds,
  private candidate filtration, archived content and inaccessible targets.
- Full Flutter analyzer, test suite, and Android signed build are
  required before APK release; a native installed test is still needed.

## Two-device acceptance
1. Upgrade APK in place; do not clear app data.
2. Create one shared rich-text note. Save and reopen.
3. Link a shared checklist, calendar event, occasion, and experience.
4. The other phone sees links and opens the *same* source records.
5. Change a linked object's title; reopen the note and confirm latest title.
6. In a private note, link a private occasion; confirm the other partner
   cannot see the note or reference.
7. In a shared note, the picker must not offer a private surprise.
8. Unlink a checklist; original checklist and all subtasks must remain.
9. Test duplicate linking, archived note read-only mode, revocation
   and opening a source the user has lost access to.
10. Reconfirm R34 checklist expansion and R37 voice controls,
    R35 occasion reminders and two-way Firebase gestures still work.

## Limitations / next slice
- Backlinks on the source object ("Related notes") and links to
  travel documents will be separate R39 work after the basic
  authorized references pass both-device testing.
- Links are not automatically extracted from note text. The user
  chooses the source explicitly, preserving intention and privacy.
