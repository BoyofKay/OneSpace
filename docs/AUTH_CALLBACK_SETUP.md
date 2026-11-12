# OneSpace Preview — Email Confirmation and Password Recovery

## Why this exists

Supabase Auth sends email links for confirming a new account or resetting a password.
The app now contains an Android auth callback and password recovery screens, but Supabase
must approve the destination. Until the approved callback is configured, a reset or
confirmation link may lead to the default Site URL rather than the app, or requests may fail.

## One required Supabase dashboard setting

Project: **OneSpace** (`ugwrpeduzyzrujkizqfo`).

1. Open [Supabase → Authentication → URL Configuration](https://supabase.com/dashboard/project/ugwrpeduzyzrujkizqfo/auth/url-configuration).
2. Under **Redirect URLs / Additional Redirect URLs**, add this exact URL:
   `onespace-preview://auth-callback/`
3. Save changes. Keep existing valid redirect URLs.
4. Ensure the email provider and **Confirm email** configuration are as intended.
5. For testers beyond Supabase's default email quotas, configure a supported
   external SMTP sender before sending frequent account emails.

Do not paste or commit SMTP credentials, service-role keys or secret keys.

## Android preview behavior

- Sign-up supplies `emailRedirectTo` pointing at the callback above.
- Resend confirmation supplies the same `emailRedirectTo`.
- Forgot password calls `resetPasswordForEmail(email, redirectTo: callback)`.
- When a reset email returns through the Android deep link, the Supabase Flutter
  library processes it; the auth gate displays a **new password** screen.
- After changing the password, the app signs out and requires normal sign-in.
- The callback is registered in the debug Android manifest only; do not use the
  preview URI for future production packages.
- The preview uses a custom URI scheme. For production, plan verified HTTPS app
  links and registered domains to reduce link-interception risk.

## Test gate (must be done on device to mark complete)

- [ ] New user receives confirmation email, taps link on Android, sees signed-in app.
- [ ] Resending verification works and older links expire as expected.
- [ ] Existing user requests recovery from sign-in; link returns to app.
- [ ] New password screen validates strength and matching confirmation.
- [ ] Reset password updates successfully and returns user to sign-in.
- [ ] Old password cannot sign in; new password works.
- [ ] Link replay and expired tokens do not grant access.
- [ ] Confirm the process on two physical test accounts/devices.
- [ ] Verify the provider's SMTP/rate limits are adequate.

The code and unit validation checks alone are **not** proof that the email-to-app
flow works. The backend redirect configuration and real email delivery need validation.
