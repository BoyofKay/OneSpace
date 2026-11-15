# R63 — iPhone groundwork (Android unchanged in behaviour)

Require-Firebase-Config: true

Previous signed preview: 0.1.429 (R62).
Preserve the existing com.onespace.onespace.preview Android package,
same signing certificate, Firebase config, biometrics, all account and
partner pairing data, checklists, notes, memories and user documents.
INSTALL AS AN IN-PLACE UPDATE only. Never uninstall or clear data.

## Included since 0.1.429
- Android: push registration and scrapbook export code paths now also
  allow iPhone; no Android behaviour change. Re-check one push arrives.
- iOS: Swift code, permissions, icons, unsigned build (see docs/IOS_SETUP.md).

## Database
- No database change. Push worker redeployed with iPhone (APNs) settings.

## Verification
- "Verify OneSpace iteration" passed on r63-ios.

## Two-phone validation
Follow docs/R62_QA.md (Arabic) and confirm push still arrives on Android.

Controlled R63 signed preview candidate, November 15, 2026.
