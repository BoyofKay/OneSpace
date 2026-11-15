# R53–R54 — Links between items and polish

Require-Firebase-Config: true

Previous signed preview: 0.1.420 (R49–R52).
Preserve the existing com.onespace.onespace.preview Android package,
same signing certificate, Firebase config, biometrics, all account and
partner pairing data, checklists, notes, memories and user documents.
INSTALL AS AN IN-PLACE UPDATE only. Never uninstall or clear data.

## Included since 0.1.420
- R53: Create from this (reminder, event, to-do, note, trip and
  type-specific actions), Linked items strip with Unlink, privacy-safe
  links, trip completion updates "last time we met" when apart.
- R54: Activities change log, On this day on Today, "Showing: Removed"
  line, contacts and Items to sort in search, completed/cancelled look.

## Database
- Applied live before this build (additive, non-destructive):
  0113 r53_links (+ trip end), 0114 r54 polish.

## Verification
- "Verify OneSpace iteration" passed on r53-links and r54-polish.

## Two-phone validation
Follow docs/R53_R54_QA.md (11 steps).

Controlled R53-R54 signed preview candidate, November 15, 2026.
