# R40 — UX consistency foundation, actionable history and contrast

Require-Firebase-Config: true

Previous published signed preview: 0.1.414. Update both existing Android
phones IN PLACE. Preserve com.onespace.onespace.preview, exact signing
certificate, Firebase registrations, both accounts, pairing, existing
checklists, notes, private surprises, messages, files and push settings.
NEVER uninstall or clear user data during upgrade.

## Features included
- Common top History/Filters controls introduced in Goals, Memories,
  Notes, Reminders. Existing top controls in other screens preserved.
- Archived history is separately toggled at the top, filters are in
  a top-right sheet, reset is available.
- Local Goals title/description and Reminders title/details search.
- Global search adds goals/memories, top category selector, accurate
  direct goal, memory and task deep links, with existing RLS.
- Action history button for notes, goals, memories, reminders, task
  checklists, calendar events, occasions and experiences.
- Backend R40 record_action_history append-only future-change events
  use authenticated actor, changed field names and server timestamp.
  No private bodies or media are copied to history.
- Rich-text Quill note @partner insertion for editable shared notes;
  existing authorized note mention triggers remain source of truth.
- Semantic theme error colors in Notes, Memories and Goals.
- All R34 checklist expansion, R35 occasion reminders, R36 private
  love self-reminders, R37 native checklist speech, R38 notes linking
  and R39 lazy backlinks must continue working.

## Backend gates already passed
- Additive 0103 deployed for eight core audit record kinds.
- Dual-partner rollback-only SQL 0024 PASSED for create/edit/archive/
  restore, authenticated actor and timestamps, changed fields and
  isolation of private notes.
- No existing note/task/occasion/memory/goal/reminder records wiped or
  mutated by migration, only future action metadata is recorded.

## Mandatory release validation
- Use committed Flutter lockfile and full test suite, analyzer, all
  new widget tests including RecordListTopActions and theme contrast
  across palette x brightness x seasonal appearances.
- Compile Kotlin Android, verify existing Firebase google-services.json,
  unchanged application package and signing certificate.
- Do not publish if any analyzer, test, compile, sign or verification
  gate fails. One verifiable signed APK asset only.
- Do NOT mark all screen UX consistency or two-phone device testing
  complete; documented remaining work in
  docs/R40_UX_CONSISTENCY_AUDIT.md.
- Real-device QA: Top history and filters in Goals, Memories, Notes
  and Reminders; private audit actions; Quill mentions; search deep
  links; four palettes; checklist open/read; notifications and privacy.

Controlled R40 candidate, November 14 2026.
Source commit 6eefbd4a5c5a6208869eb0df97326af2cef403fd.
