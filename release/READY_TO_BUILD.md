# OneSpace QA — branded invitation email correction (2026-11-19)

Require-Firebase-Config: true

Build signed installable QA APK, package onespace.qa / QA Supabase.
Changes:
- Gmail email draft spaces are percent encoded (no literal + signs)
- Email sharing offers a real HTML branded invitation from OneSpace
- Clickable email CTA, logo, tagline, readable manual code fallback
- Google Play/App Store placeholders stay non-clickable until links exist
- Secure authenticated server sender and private rate limits; both backend
  environments have migration and matching Edge functions deployed
- WhatsApp, SMS, resend, replacement and pairing remain unchanged

Test locked dependencies, Flutter analyze and tests, Android signing/package,
Firebase config, plus unsigned QA/Production iOS compile.
Do not automatically deploy to Google Play or TestFlight.
