# R74 — Ready for test couples

Require-Firebase-Config: true

Previous signed preview: 0.1.438 (R73).
Preserve the existing com.onespace.onespace.preview Android package,
same signing certificate, Firebase config, biometrics, all account and
partner pairing data, checklists, notes, memories and user documents.
INSTALL AS AN IN-PLACE UPDATE only. Never uninstall or clear data.

## Included since 0.1.438
- Terms of use on sign-up (and once for existing accounts).
- Google / Apple sign-in (buttons appear once enabled in Supabase).
- Help, Contact us and Report a problem on the sign-in screen.
- Automatic error reports (no content).
- Show in my phone calendar (one way, separate OneSpace calendar; calendar permission).
- Tablet layout frame.
- Fix: email confirmation and password-reset links now return to the installed app.

## Database
- 0128_r74_terms_public_help_errors (applied 16 Nov, tested).

## Verification
- "Verify OneSpace iteration" and "iOS build" passed on r74-testers-ready.
