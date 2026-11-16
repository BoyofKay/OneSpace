# R74 — what only Ahmed can set up

## 1. Google sign-in (about 15 minutes)
1. https://console.cloud.google.com → create/choose a project → APIs & Services → OAuth consent screen: External, app name "OneSpace", your email, add the 4 tester emails as test users (or publish).
2. Credentials → Create credentials → OAuth client ID → **Web application**.
   Authorized redirect URI: `https://ugwrpeduzyzrujkizqfo.supabase.co/auth/v1/callback`
3. Supabase dashboard → Authentication → Sign In / Providers → Google → enable, paste Client ID and Client secret → Save.
4. Supabase → Authentication → URL Configuration → Redirect URLs: make sure `onespace-preview://auth-callback/` is listed.
The "Continue with Google" button appears in the app by itself once step 3 is saved.

## 2. Apple sign-in (needs the Apple Developer account, $99/year)
1. developer.apple.com → Identifiers → App ID with "Sign in with Apple"; then a **Services ID** (e.g. com.onespace.signin) with Sign in with Apple, domain `ugwrpeduzyzrujkizqfo.supabase.co`, return URL `https://ugwrpeduzyzrujkizqfo.supabase.co/auth/v1/callback`.
2. Keys → new key with Sign in with Apple → download the .p8 (once).
3. Supabase → Providers → Apple → enable; Services ID, Team ID, Key ID and the .p8 (Supabase generates the secret; it expires every 6 months — set a reminder).
Apple's rule: an iPhone app that offers Google sign-in must also offer Apple.

## 3. Nightly database backups
GitHub → BoyofKay/OneSpace → Settings → Secrets and variables → Actions → New repository secret:
- `SUPABASE_DB_URL` = Supabase → Connect → **Session pooler** URI (replace [YOUR-PASSWORD]).
- `BACKUP_PASSPHRASE` = a long passphrase you keep in your password manager.
Then Actions → "Back up OneSpace database" → Run workflow once to check. Backups are kept 14 days.

## 4. Supabase settings worth switching on
- Authentication → Attack protection → Leaked password protection (Pro plan only; skip on Free).
- Authentication → Email: keep "Confirm email" on.

## 5. Where to look during the test
- Messages from testers: tables `support_requests` (signed in) and `public_support_requests` (from the sign-in screen).
- Automatic error reports: table `client_errors` (newest first).
- Supabase → Reports for usage; Firebase console → Cloud Messaging for push.
