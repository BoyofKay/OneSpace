# R12 — Final release candidate

Iteration: R12 — Contact cards, Love Gesture pools, Check-in clarity and Letters
Previous confirmed APK: preview-0.1.395

Changes:
- Standalone Contacts independent of Activities and a reusable Contact Card editor.
- Collapsible cards, origin-specific links, private/shared choice and edit history.
- Soft removal and restoration; 30-day purge eligibility for standalone contacts
  without automatic irreversible deletion.
- Readable daily feelings and check-in request/response logs.
- Editable user-specific preset message overrides, grouped message pools by
  gesture type and randomized combined manual sending.
- Gesture management only in Settings, separate Thoughtful Rituals controls.
- Gesture-specific notification icons, strength and togetherness symbols.
- A Little Love shortcut on Today.
- Letter detail fetched by ID with independent read receipt and reply loading.
- Days Off editor simplified to date and label; normal sleep schedule respected.
- Database RLS, owner checks, revision auditing and regression tests.

Validation-only run 2 passed: https://github.com/BoyofKay/OneSpace/actions/runs/43433870843

Trigger exactly one signed APK release for this completed iteration.
Do not alter the marker until R13.
