# R58 — Fix: ⋮ menu crash inside an Activity

Require-Firebase-Config: true

Previous signed preview: 0.1.424 (R57).
Preserve the existing com.onespace.onespace.preview Android package,
same signing certificate, Firebase config, biometrics, all account and
partner pairing data, checklists, notes, memories and user documents.
INSTALL AS AN IN-PLACE UPDATE only. Never uninstall or clear data.

## Included since 0.1.424
- Fix: tapping ⋮ inside an Activity crashed ("RenderBox was not laid out").
  Menus now measure their position once, when tapped (all ⋮ menus, plus the
  priority/status/outcome menus inside an Activity).

## Database
- No database change in R56.

## Verification
- "Verify OneSpace iteration" passed on r58-menu-fix.

## Two-phone validation
Open an Activity, tap ⋮ and each toolbar menu; then continue docs/R57_QA.md.

Controlled R58 signed preview candidate, November 15, 2026.
