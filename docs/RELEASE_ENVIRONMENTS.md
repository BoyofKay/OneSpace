# OneSpace environments: QA and Production

Since 17 Nov 2026 OneSpace exists as **two separate apps with two separate backends**.
They install side by side on one phone and never share data.

| | **OneSpace QA** | **OneSpace** (production) |
|---|---|---|
| Who | Ahmed and testers checking each new build | Real couples (Founders first) |
| Android package | `onespace.qa` | `live.onespace.app` (permanent once on Play) |
| Name / icon | "OneSpace QA", amber icon with a QA badge | "OneSpace" |
| Backend | Supabase project **OneSpace** (`ugwrpeduzyzrujkizqfo`, Seoul) — test users and demo data only | Supabase project **OneSpace Production** (`letcgxbnblohhfyeuigz`, Frankfurt) — clean start |
| Sign-in callback | `onespace-preview://auth-callback/` | `onespace://auth-callback/` |
| Signed with | Test key in `tools/dev-signing/` (public, never for Play) | Play **upload key** from GitHub secrets; Google re-signs with the Play app signing key |
| Built by | `.github/workflows/android-dev.yml` → APK in GitHub Releases (`qa-0.1.N`) | `.github/workflows/android-play.yml` (manual) → `.aab` in the run's Artifacts |
| Distributed | GitHub Releases APK | Play Console: closed testing (Founders = UAT) → production |

UAT is **not** a third app: it is the exact production build on the Play closed-testing
track. When it passes, the same build is promoted to production.

## How the app picks its backend

`lib/core/app_env.dart` holds both backends. The build passes
`--dart-define=ONESPACE_ENV=qa` or `--dart-define=ONESPACE_ENV=production`; anything that is
not `production` is QA, so a build can never reach real couples by accident. The Android flavor
(`--flavor qa` / `--flavor prod`) sets the package, label, icon and callback scheme.

```bash
# QA APK
flutter build apk --release --flavor qa --dart-define=ONESPACE_ENV=qa
# Production bundle for Play (needs the upload key environment variables)
flutter build appbundle --release --flavor prod --dart-define=ONESPACE_ENV=production
```

`android-play.yml` refuses to build while `app_env.dart` still has placeholder production
values, without the upload key, or (unless you tick *allow_without_push*) without a Firebase app
for `live.onespace.app`.

## One-time setup checklist (Ahmed)

### GitHub secrets — `BoyofKay/onespace` → Settings → Secrets and variables → Actions
| Secret | Value |
|---|---|
| `ONESPACE_UPLOAD_KEYSTORE_BASE64` | content of `onespace-upload.jks.base64.txt` (sent privately) |
| `ONESPACE_UPLOAD_STORE_PASSWORD` | from `README-upload-key.txt` |
| `ONESPACE_UPLOAD_KEY_PASSWORD` | from `README-upload-key.txt` |
| `ONESPACE_UPLOAD_KEY_ALIAS` | `onespace-upload` |
| `ONESPACE_GOOGLE_SERVICES_JSON_BASE64` | update after adding the two Firebase apps below |

### Firebase (same Firebase project for both apps)
Add two Android apps, then download the new `google-services.json` (it covers all apps) and
replace the secret with its base64:
- `onespace.qa` — SHA-1 `A0:47:86:BF:75:A5:EA:CA:89:DF:43:83:91:3D:08:FF:51:CF:49:16`
- `live.onespace.app` — upload key SHA-1 `D1:6A:CF:3A:DE:96:A3:33:AA:69:52:23:9B:E6:4E:EE:09:F3:DB:85`,
  plus the **Play app signing** SHA-1 shown in Play Console → Setup → App signing (after the first upload).

Until then QA builds still work, with in-app notifications only.

### Supabase — OneSpace Production project (dashboard)
- **Edge Function secrets:** `ONESPACE_FIREBASE_SERVICE_ACCOUNT_JSON` (same Firebase service account
  JSON as QA), `RESEND_API_KEY`, `FOUNDER_ADMIN_KEY`, `GOATCOUNTER_TOKEN`.
  (No `ONESPACE_PUSH_CRON_SECRET` needed: the push and account-purge workers read the shared secret
  from Vault through `public.push_worker_secret()`, service role only — migration 0136.)
- **Authentication → URL Configuration:** Site URL `https://onespace.live`; Redirect URLs
  `onespace://auth-callback/`.
- **Authentication → Providers:** Google (and Apple later) with an Android OAuth client for
  `live.onespace.app` and the Play signing + upload SHA-1s.
- **Authentication → Emails / SMTP:** same sender setup as QA (e.g. Resend SMTP) so confirmation
  emails come from onespace.live.

### Supabase — OneSpace (QA) project
Nothing changes: it keeps `onespace-preview://auth-callback/`, its users and data. Optionally
rename it to "OneSpace QA" in Settings → General.

## Database changes from now on
Every migration is applied to **QA first**, tested with the QA app, and only then to Production.
Never test a migration on Production.

## Moving testers
The old preview app (`com.onespace.onespace.preview`) stops receiving updates. Testers uninstall it
and install **OneSpace QA** from the newest `qa-0.1.N` GitHub release.

## How Production was created (17 Nov 2026)
- The 149 QA migrations were replayed in order into the new project (project URL rewritten), then a
  catalog comparison against QA found objects that had been made in QA outside migrations
  (tables `record_action_history`, `note_references`, `partner_checkin_acknowledgements`,
  `shared_experience_interests`, some columns, constraints, triggers, policies, function grants).
  They were copied exactly, and the final comparison showed no differences. Storage buckets,
  storage policies and the 7 pg_cron jobs match (jobs point at the production URL).
- No app data was copied. Only the Founder waitlist (couple #1) moved from QA to Production.
- **Lesson:** every database change must be a migration. Changes made with ad-hoc SQL do not reach
  Production.

## Public website URLs for Google Play and iOS listings

Use the canonical clean URLs in store consoles, release notes, marketing and any future in-app external links:

- Privacy policy: `https://onespace.live/privacy/`
- Terms of use: `https://onespace.live/terms/`
- Account deletion: `https://onespace.live/delete-account/`
- Customer support: `https://onespace.live/support/`
- Frequently asked questions: `https://onespace.live/faq/`
- Founder signup: `https://onespace.live/join/`

The website serves localized clean links under `/ar/`, `/es/`, `/fr/`, and `/de/`, and keeps the previous `.html` addresses as backward-compatible redirects. In-app Terms and Privacy screens are native and must remain consistent with these hosted policies. These documentation-only updates do not change the signed Android AAB or iOS build.

## iOS identity and release isolation (18 November 2026)

The iOS release branch ios/launch-readiness-20261118 adds separate native QA
(com.onespace.onespace.qa) and production (com.onespace.onespace) identities,
matching auth callback schemes and a fail-closed startup check before the app
opens Supabase. See docs/IOS_SETUP.md for the explicit environment command,
manual unsigned QA build, manual signed production/TestFlight pipeline and
Apple/Firebase prerequisites. New iOS code still requires compile, signing
and real-device acceptance before merging/releasing.
