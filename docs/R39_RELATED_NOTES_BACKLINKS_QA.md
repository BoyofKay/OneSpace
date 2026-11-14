# R39 — Related Notes from original OneSpace records

## Purpose
Complete the two-way workflow started in R38: a rich text note can link
a checklist, event, occasion or shared experience; now the original
item can also show the accessible notes linked to it.

## Delivered source
- In expanded To-do and Checklists, a **Related notes** panel, collapsed
  by default, below the checklist. This preserves the R34 repaired
  ExpansionTile/scroll key handling and adds no query until expanded.
- Occasion and Surprise details show a collapsed Related notes panel.
- Shared Experience details show a collapsed Related notes panel.
- Calendar event's action menu offers **Related notes**, which opens an
  on-demand sheet.
- Related note titles are resolved in the original `notes` table under
  the current account's RLS, never stored or copied to the backlink.
- Open a related note through NotesScreen(initialNoteId), which launches
  the existing rich-text editor with the correct read-only permissions.
- Open Notes from the panel to add a link through R38's existing
  Note References picker, then refresh the panel.
- Archived notes are labeled Archived, not silently deleted.
- Read-only panels never modify source object or note data.

## Privacy and performance
- No extra schema or FCM notifications. The R38 `note_references`
  SELECT RLS enforces that both the note and original target are
  visible; second `notes` query independently applies notes RLS.
- A private surprise note stays invisible to the other partner even
  when its target is otherwise shared.
- No data/permission is cached across sign-ins; each on-demand query
  reads only current authorized rows.
- Lazy loading avoids four extra queries per checklist until user
  explicitly opens the Related notes section.

## Tests
- R38 SQL rollback tests 0022/0023 passed and still apply.
- New `related_notes_rules_test.dart` covers authorized IDs, pin
  order and missing/inaccessible references.
- Full Flutter source analyzer + automated test suite required.
- Android signed APK and two-phone acceptance will follow only
  after R38 preview source/CI gates are passed.

## Phone acceptance (R39 release)
1. Link a shared checklist to a shared note from the R38 Notes editor.
2. Return to the checklist, expand Related notes, open the exact note.
3. Verify the other partner sees the same shared note.
4. Link a private note to a private occasion. Verify only its owner
   sees the Related notes entry.
5. Open a shared experience and a calendar event; access linked notes
   through their respective detail/action UI.
6. Change note title. Refresh the source panel to see its new title.
7. Unlink in the Notes editor; original source object remains intact,
   and its backlink disappears after refresh.
8. Check R34 checklist expansion, R37 voice readout and FCM gestures.
