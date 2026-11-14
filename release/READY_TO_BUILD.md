# R38 — Notes 2.0 Cross-Module References and Search

Require-Firebase-Config: true

Previous published preview: 0.1.413. Preserve the same
com.onespace.onespace.preview Android package, stable preview signing
certificate, two accounts, pairing, all notes, private surprises,
original source objects and Firebase Android configuration.
Only install over the existing APK; never uninstall or clear data.

## New in this release
- Notes rich editor can link accessible checklist, calendar event,
  occasion/surprise, and shared experience records.
- Links navigate to original items; their titles are fetched live under
  original source-table RLS. Unlink never deletes the source.
- Private note links stay private and cannot leak a private surprise
  through a shared note. Private view-only recipients cannot edit links.
- Duplicate links rejected; archived notes retain read-only references.
- Notes list now supports title/body search while preserving pinning,
  Shared/Private filters and archived history.
- All existing R34 recovered checklist expansion, R35 occasion reminders,
  R36 love self-reminders and R37 native checklist speech are included.

## Database verification complete
- Additive 0101 note reference table plus RLS source validation DEPLOYED.
- Additive 0102 view-only private link edit protection DEPLOYED.
- SQL rollback regression 0022 PASS: dual account, shared/private
  segregation, wrong target, duplicate, read and unlink.
- SQL rollback regression 0023 PASS: real private occasion cannot be
  linked into a shared note or exposed to the other partner.
- No existing notes, objects, visibility, accounts or data reset.

## Mandatory publication gates
- Run Flutter locked dependencies, analyze, all unit/widget tests
  including notes_library_rules_test and note_reference_rules_test.
- Android native compilation; signed preview APK validation.
- Verify same package/signing certificate and Firebase config.
- Publish one verifiable GitHub Release asset, no hidden data migration.
- QA docs/R38_NOTES_LINKED_REFERENCES_QA.md.
- Do not claim actual phone acceptance until testing on both phones.
- Halt publication if analyzer, tests, Kotlin, signing or verification fails.

Controlled Android R38 preview candidate, 14 November 2026,
source SHA 736bcc2d9cf134c7ad4cccdb0049fb56e2f53396.
