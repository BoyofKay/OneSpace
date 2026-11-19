# OneSpace QA — Pairing & Separation Lifecycle: first safe implementation slice

Require-Firebase-Config: true
Target: QA only. No Production AAB, TestFlight or Production backend changes.
Branch: qa/lifecycle-first-slice-20261119

QA source:
- Dedicated Change password subpage (3 fields, plain reset-email CTA)
- Dedicated Invite my partner page (recipient email required, QR/code/copy)
- Creator-only addressed invitation, same-code resend, confirmed replace/revoke
- Recipient verified-email match enforced in QA server RPC
- Invitation deep-link pairing after signup and verification
- Recipient-locked branded email service (QA only)
- Read-only My Space profile section

Safety: leave/remove/delete/archive purge are intentionally NOT enabled
until personal vault migration and archive validation are safe.
Build/test/verify signed QA APK, keep Production entirely untouched.
