# OneSpace QA — solo invitation and secure password manager release (2026-11-19)

Require-Firebase-Config: true

One verified QA Android APK for package onespace.qa + Supabase QA only.
The same release marker requests *unsigned* QA and Production iOS compile
archives; Apple signing/TestFlight delivery remains separately gated.

Included source changes on main:
- Collapsible Today invitation card; resend existing code as main action
- Confirmation before replacing and invalidating an invitation
- Friendly Email, WhatsApp, SMS link and manual QR/code fallback
- Invitation URL intake respecting QA and Production environments
- Password-manager autofill hints, account identification and safe
  forgot-current-password email recovery within profile settings

Checks: flutter analyze/test, locked dependencies, Android QA sign/label,
Firebase configuration, publish APK release; iOS builds are unsigned only.
Do not promote this mobile release to general availability before device QA.
