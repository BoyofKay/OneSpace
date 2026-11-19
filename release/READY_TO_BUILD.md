# OneSpace QA — invitation and canonical branding closure
Require-Firebase-Config: true

## One signed QA APK only
- Source includes merged PR #74 (invitation signup/signin), PR #75 (approved
  exact tagline `Two of Us. One Space`), and PR #76 (stable QA signing
  certificate and aligned source for email templates), and PR #77 (safe
  certificate-check pipeline; original signing fingerprint remains required).
- Android package: `onespace.qa`.
- Dart target: `ONESPACE_ENV=qa`; QA Supabase project
  `ugwrpeduzyzrujkizqfo`. Production Supabase untouched.
- Assert original QA signing SHA-256
  `90375bb8d7dbd6527cca17f626da149534eaffe10076c38a5c69ac86a3aac043`.
  Any mismatch must fail the build; never silently rotate QA keys.
- Flutter analysis + tests, Firebase QA package, APK package name and signed
  APK publication must all pass before considering this release available.

## Real device acceptance before closing
1. Install QA APK **over** existing QA app (do not uninstall and lose a
   saved incoming invitation).
2. New invited user: latest invitation, signup, dedicated confirm-email page,
   click confirmation email, sign in, automatically join existing space.
3. Existing invited user: latest invitation, sign in, automatically join.
4. Wrong account cannot redeem; current invitation must not be treated as a
   replaced/expired link.
5. QA Supabase hosted Confirm signup + Reset password templates still need
   matching HTML applied in dashboard; source-only commit does not update
   hosted Auth settings. Send real emails and verify logo + link.
6. No QA record deletion, space/account separation or Production database
   changes during this release.

## Future roadmap (NOT an excuse to block safe invitation testing)
- Founder expressly authorizes a QA-only historical record reset if needed
  for structural redesign of ownership tables.
- Structured private and shared content must remain eligible for archive and
  restore. Uploaded media, photos and documents are **excluded** with a
  clear user-facing disclosure. Do not remove all archive/restore features.
- Do not enable destructive lifecycle actions until ownership and structured
  restore are proven safe.
