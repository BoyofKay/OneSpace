# QA Auth password-reset sender — configuration gate

**Finding:** Password reset emails originate from Supabase Auth's built-in SMTP. The app's separate `invitations@onespace.live` Resend Edge Function does **not** set the Auth mail sender. The QA screen is correct; the sender still displays `Supabase Auth` and `noreply@mail.app.supabase.io` until Auth SMTP is configured.

**Desired sender**: `OneSpace <support@onespace.live>`. First verify that `onespace.live` is authorized to send from `support@` in the current email provider and SPF/DKIM are properly configured.

**QA only — required operator action in Supabase Dashboard (not exposed by current connector):**
1. QA project > Authentication > SMTP Settings: enable custom SMTP. Use a verified provider (e.g. Resend SMTP `smtp.resend.com`, port 465/587 based on documented settings), configured credentials from the provider's secrets store. **Do not commit API keys to GitHub.**
2. Set sender name **OneSpace**, sender address **support@onespace.live**.
3. Authentication > Email Templates > Reset Password: use `supabase/email-templates/password_recovery.html`, preserving Supabase's `{{ .ConfirmationURL }}` replacement variable.
4. Check verified sender identity (SPF/DKIM/DMARC), SMTP quotas/rate limits, and return URL `onespace-preview://auth-callback/`.
5. Test **Send a reset email** while signed in and **Forgot password** when signed out with a fresh QA test account. Verify the message's real From headers, not only its displayed name, and ensure secure app callback and password recovery.
6. Repeat separately for Production **only after the QA test is accepted**.

**Current status**: template committed; Auth SMTP is **not configured or independently verified** by this change. No custom password emails are sent using an administrator bypass. Keep the standard secure Supabase recovery flow until proper SMTP is available.

Source: https://supabase.com/docs/guides/auth/auth-smtp
