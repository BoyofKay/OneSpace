# OneSpace QA — invitation handoff and environment isolation
Require-Firebase-Config: true

## Build exactly one signed Android QA APK
QA package: `onespace.qa`.
Dart define: `ONESPACE_ENV=qa`.
QA Supabase: `ugwrpeduzyzrujkizqfo`.
This build MUST be from main containing merged PR #74.

## Included and verified
- Dedicated signup email confirmation page with resend and Sign in controls.
- Invitation persists across signup, email confirmation and existing-account sign-in.
- QA-only secure resolve for the intended recipient's replaced invitation, then
  accept_invitation with verified email; forwarded/wrong-account code denied.
- On unpaired sign-in show focused joining flow instead of three setup cards.
- Precise failed-invitation messaging, retry and sign-in with correct email.
- Android startup verifies installed package and backend target before Supabase.initialize.
  Production package live.onespace.app cannot connect to QA and vice versa.
- Android NDK SDK installation retries corrupt downloads and verifies revision.

## CI release gate
- Locked dependencies, Flutter analyzer and all widget/unit tests.
- Correct Firebase QA app, package ID, signed QA certificate and artifact.
- Tag and asset must point to the exact triggering commit on main.
- No Production DB changes, no user/space/invitation deletion.
- No production AAB / Play deployment.

## Device QA acceptance
1. A invites B via email and receives an active code.
2. New B opens invitation, creates an account, sees full Confirm email page,
   confirms email, signs in, automatically joins A's existing space.
3. Existing unpaired B follows invitation and signs in; same result.
4. Older replaced link resolves ONLY if same verified recipient and same space.
5. Wrong email, expired, revoked-with-no-replacement and already paired
   show specific guidance; never join another account without permission.
6. Confirmation email branding template must be activated separately under
   QA Supabase Auth Email Templates (source committed, not deployed automatically).
7. Both Android test devices, Firebase push and upgrade installation.
