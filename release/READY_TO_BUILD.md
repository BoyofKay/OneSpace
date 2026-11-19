# OneSpace QA — password-recovery navigation fix (2026-11-19)

Require-Firebase-Config: true

Build ONE signed installable OneSpace QA APK (Android package `onespace.qa`)
with the QA Supabase environment `ugwrpeduzyzrujkizqfo`. This is a
QA-only validation candidate, not a Production/Google Play release.

## Included fix (merged PR #69)

- Requesting password recovery from signed-in Profile closes the
  Change password dialog after Supabase accepts the email request.
- A verified recovery email link brings Set a new password to the front,
  clearing Profile/dialog routes without requiring Cancel and Back.
- Signed-out Forgot password retains the same verified-link security flow.
- Existing password remains valid until the new password is successfully saved;
  cancelling recovery must not replace the password.
- English and Arabic recovery text updated.
- Regression assertion added to the Flutter recovery widget tests.

## Release checks

Use the committed dependency lockfile, run Flutter analysis and all tests,
build the QA APK with QA flavor/environment, validate Firebase QA config,
APK package ID and signature, retain artifact, then publish the single
verified signed APK to the QA GitHub Release.

## Manual QA acceptance after installing

1. From Profile > Change password > Forgot current password, request
   a reset; confirm the modal closes instead of covering the reset page.
2. Open that email's verified link: Set a new password must be visible
   immediately, without Cancel or Back.
3. From signed-out Forgot password, confirm the same secure destination.
4. Before submitting a new password (or after cancelling recovery),
   the old password must still work.
5. After a successful new-password submission, the old password must fail
   and the new password must work; require reauthentication.
6. Exercise invalid, expired, reused or wrong-environment links, password
   policy rejection, English/Arabic and both QA Android phones.

Do not deploy to Production, Google Play or TestFlight.
