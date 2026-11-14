# R24 — Firebase Cloud Messaging groundwork and secure push transport

Previous signed preview 0.1.401. Upgrade IN PLACE; never uninstall or clear app data.

## Included in this controlled Android preview
- Firebase Core 5.1.0 and Firebase Messaging 17.0.1, committed lockfile.
- Graceful Firebase initialization after a valid Supabase session has been unlocked; unconfigured Firebase must NOT block login or in-app alerts.
- Android 13+ notifications permission request and device token/refresh registration as the authenticated user.
- Native system alert taps navigate to the in-app OneSpace notification feed while unlocked.
- Explicit sign-out deactivates the device's push registration before ending its Supabase session.
- Native Google Services Gradle integration only for an Android Firebase configuration matching com.onespace.onespace.preview, delivered securely by GitHub Actions secret ONESPACE_GOOGLE_SERVICES_JSON_BASE64.
- Supabase 0087–0088: private owner-only device registration, outbox idempotency, service-only claim/ack, retries, optional pg_net schedule transport.
- Deployed Supabase Edge Function onespace-push-delivery: Google OAuth 2.0 signed JWT with FCM HTTP v1, authorization by ONESPACE_PUSH_CRON_SECRET, lock-screen-safe generic text, invalid-token retirement, transient retry.
- SQL regression test 0012 PASSED under rollback; private devices/partner isolation, exactly-one enqueue and service-only acknowledgement.
- Full Flutter analysis and tests green on R24 candidate, GitHub run 43607044157.
- User setup instructions: docs/FIREBASE_PUSH_SETUP.md.

## IMPORTANT: Do not misrepresent live push
The Firebase Android config and server-side service-account credentials have not been supplied by the user yet. This Android preview can install and use existing in-app notifications, but background Firebase pushes are NOT active until:
  1. User registers com.onespace.onespace.preview with Firebase.
  2. GitHub secret ONESPACE_GOOGLE_SERVICES_JSON_BASE64 is set and a new APK built with it.
  3. Supabase Edge Function secrets ONESPACE_FIREBASE_SERVICE_ACCOUNT_JSON and ONESPACE_PUSH_CRON_SECRET are set.
  4. Matching Vault secret and scheduled worker job are activated as documented.
Do not package or publish private Firebase server keys.

## Release acceptance gates
Pinned Flutter dependencies and lockfile unchanged, flutter analyze, flutter test, Gradle optimized APK build, unchanged Android preview signing key and com.onespace.onespace.preview package, retained workflow artifact and release asset. Publish one candidate only if green.

## Still pending from the wider roadmap
Collaborative scrapbook templates, offline Trips documents, enriched Shared Experiences, Games external invitation, a thoughtful private love-suggestion engine, AI assisted summaries and voice read-aloud commands, iOS extensions and iPhone push registration. Not included in R24.

R24 integration marker, 2026-11-14.
