# R73 — Experiences polish, support screenshot, invitation QR, Arabic sweep

Require-Firebase-Config: true

Previous signed preview: 0.1.437 (R72).
Preserve the existing com.onespace.onespace.preview Android package,
same signing certificate, Firebase config, biometrics, all account and
partner pairing data, checklists, notes, memories and user documents.
INSTALL AS AN IN-PLACE UPDATE only. Never uninstall or clear data.

## Included since 0.1.437
- Shared experiences: ratings on cards, tap a pick again to clear it, one ⋮ on the page, no notes panel, Activity-style conversation with replies.
- Report a technical issue: attach a screenshot.
- Invitation: QR code to scan, and a scanner on the join screen (camera permission).
- Arabic: joined lines translated piece by piece, ~60 sentence patterns, ~70 phrases.

## Database
- 0126_r73_experience_replies, 0127_r73_support_screenshot (applied 16 Nov, tested).

## Verification
- "Verify OneSpace iteration" passed on r73-experiences-polish.
