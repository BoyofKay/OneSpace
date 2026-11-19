# Solo-user QA — Gmail invitation rendering and branded email

Reported: 19 Nov 2026. The original Gmail draft showed literal plus signs
in the subject and body and did not render the link as a button.

## Root cause
Flutter `Uri(queryParameters:)` uses form-query encoding and replaces
spaces with '+'; RFC 6068 mailto expects '%20'. Email clients vary in
whether a URL looks hyperlinked while a draft is being composed.

## New delivery paths
- **Email → Send branded email**: enter partner's email. Supabase Edge
  Function `onespace-send-invitation` reads the existing active token
  under the signed-in creator's RLS. Sends HTML + plaintext using the
  provider's server-side RESEND_API_KEY.
- **Open email draft**: corrected RFC 6068 percent-encoded plain text.
  Does not claim to support logo images or official store artwork.
- Both use the **same active code**; no replacement and no expiry extension.
- Branded HTML uses the existing OneSpace website logo and official tagline
  "Two of Us. One Space."; clickable call-to-action and visible fallback
  link. When a store's real product link is not configured, show a
  nonclickable "Coming soon" object, never a fake store destination.
  Once real store links are configured via ONESPACE_PLAY_STORE_URL and
  ONESPACE_APP_STORE_URL, render the official provider badges with links.

## Security
- Authenticated only (verify_jwt=true and /auth/v1/user validated).
- The server looks up the invitation using the user's access token;
  client-supplied tokens/forged sender names are ignored.
- Rate-limit guard is service-role-only: 5 sends per user per hour;
  at most one per recipient per 15 minutes. Only hashed recipient IDs
  appear in the private sending log; never passwords or raw email.
- Invalid/revoked/expired/other people's invitations are refused.
- Domain's Resend API key never appears in app or web code.
- Do not invite anyone until user explicitly presses Send branded email.

## Verification
1. QA Android: Email → Open email draft in Gmail. No literal '+'
   characters for spaces; subject/body are readable and text is spaced.
2. Email → send branded email to an **authorized test address** and read the
   actual delivered HTML email in Gmail; images load, invitation CTA is
   clickable, same 64-char code and expiry as the Today card.
3. Unavailable stores show non-clickable tiles. Never advertise an
   unapproved App Store or Play app listing as available.
4. Send twice to the same address within 15 min: second request fails.
   A different authorized recipient may receive another within hourly cap.
5. Recipient with app installed follows invitation; recipient without
   app gets manual-code fallback on /app-invite/.
6. Repeat on QA iOS; ensure sender identity and brand signature are correct.
7. Recheck endpoint accepts **no anonymous calls** and does not send
   expired/revoked/other-user invitations.
8. Production backend and app separately; do not treat a passing QA
   test as evidence that production SMTP credentials or links work.
