# OneSpace iOS — launch preparation (updated 20 November 2026)

This document separates what is already coded from what has actually been
built, signed, tested, and released. The same Flutter application is shared
between Android and iPhone. Existing native iPhone support covers picking
documents and contacts, saving contacts, file export, calendar export, voice
services, permissions, Face ID integration and Arabic permission text.

## Status

- **Founder Member badge (22 Nov 2026):** the shared Flutter Me screen already displays the unnumbered badge by calling `public.my_founder_status()`. The matching RPC, private Founder table and signup hooks are now deployed in **both** QA and Production Supabase, verified by post-deployment permissions/RLS checks and transactional founder/non-founder tests. Hardening and Production SQL audit trail: [PR #145](https://github.com/BoyofKay/OneSpace/pull/145). Real iPhone/UI acceptance still requires signed TestFlight after Apple setup.

- 20 November 2026: the iOS readiness work (formerly PRs #65 and #66) was
  re-applied on top of current main, which now includes private/shared
  spaces, the leave/remove/delete lifecycle, 7-day account deletion and the
  48-hour invitations. Signed TestFlight now supports QA and Production, and
  the app requests Universal Links for onespace.live invitations.
- An unsigned iOS compilation previously passed on 16 November 2026.
- The iOS readiness work adds separate QA/production iOS
  identifiers, callback schemes, native startup validation, APNs token
  readiness retries, Firebase plist bundling, a manual signing/TestFlight
  workflow, and a native Share Extension for links, text, images and PDFs.
  These additions are NOT yet compiled or tested on a physical iPhone.
- Signed IPA: unverified. TestFlight: not uploaded or confirmed. Apple review:
  not submitted. Firebase/APNs physical iPhone delivery: unverified.
- Android and the production Supabase database have not been modified.
- Founding 500 registration can accept both Android and iPhone visitors
  without claiming the iPhone application is published.

## Environments and identity

| Property | QA | Production |
|---|---|---|
| iPhone label | OneSpace QA | OneSpace |
| Apple bundle ID | com.onespace.onespace.qa | com.onespace.onespace |
| Dart environment | ONESPACE_ENV=qa | ONESPACE_ENV=production |
| Callback URL | onespace-preview://auth-callback/ | onespace://auth-callback/ |
| Backend | existing QA Supabase | clean production Supabase |
| Invitation link | https://onespace.live/qa-invite/ | https://onespace.live/app-invite/ |
| Distribution | TestFlight (internal testers) | TestFlight, then App Store |

For local iOS work, first run:

    python3 tools/ios/configure_env.py qa

Then build with the matching Dart define:

    flutter build ios --release --no-codesign --dart-define=ONESPACE_ENV=qa

For production, use configure_env.py production and the matching
--dart-define=ONESPACE_ENV=production. A signed build needs the Apple
Developer credentials and certificate/profile. The Flutter startup refuses
to connect to Supabase if the built-in native environment, callback and
bundle ID disagree with the Dart backend. Production app builds also verify
their packaged Firebase registration.

## Manual-only workflows

1. Build OneSpace iOS QA (unsigned) is the GitHub workflow at
   .github/workflows/ios-build.yml. It produces an unsigned diagnostic
   artifact, which CANNOT be installed directly on a normal iPhone.
   It runs manually, or automatically when release/READY_TO_BUILD.md changes
   on main (the same trigger as the Android release).
2. Build and optionally upload OneSpace iOS to TestFlight is at
   .github/workflows/ios-testflight.yml. Choose environment qa or production.
   It requires that environment's signing profiles and Firebase file,
   verifies identity, push, App Group and Associated Domains entitlements,
   exports a signed IPA, and only uploads when upload_testflight is enabled.
   Uploading to TestFlight never submits the app for App Store review.

   **QA-first promotion (owner policy, 22 November 2026).** Production can
   only be built for a commit that is on main, has a successful QA TestFlight
   upload from this workflow, and is approved in the run form:
   - `qa_tested_sha`: the full commit SHA that passed iPhone QA.
   - `release_approval`: `APPROVE PRODUCTION TESTFLIGHT`.
   A Linux gate checks this before any Mac minutes or signing secrets are
   used. The Production IPA is then rebuilt from exactly that commit with
   `ONESPACE_ENV=production`. Each run writes a release attestation (commit,
   environment, QA evidence run, who requested it, result) to the job summary
   and keeps it as an artifact for 90 days. The signing job runs in the
   `ios-qa` or `ios-production` GitHub environment, so required reviewers can
   be added to `ios-production` where the GitHub plan supports it.
   Production TestFlight is not an App Store release. Submitting for review
   stays a separate, manual decision by the owner.

Neither signed workflow runs on normal GitHub commits. Mac CI is expensive for
private repositories. Use a physical iPhone + TestFlight for actual UAT;
a Windows PC cannot run Apple's iPhone Simulator.

## Apple and Firebase account actions needed

- Enroll in the Apple Developer Program under the intended OneSpace publisher
  identity. Use a dedicated business/admin identity if possible rather than
  relying on personal email addresses for publishing. Apple Developer
  enrollment is normally US $99/year in the United States, with regional
  pricing differences.
- Create the production App ID com.onespace.onespace and enable Push
  Notifications, App Groups and Associated Domains. Register a second production App ID for
  com.onespace.onespace.ShareExtension. Associate both with App Group
  group.com.onespace.onespace and generate separate App Store provisioning
  profiles for the host and extension. For signed QA, use the analogous
  .qa app, .qa.ShareExtension and group.com.onespace.onespace.qa.
- Obtain an Apple Distribution certificate with its private key (p12),
  matching App Store provisioning profile and Apple Team ID. For production
  the provisioning profile must contain the production APNs entitlement.
- In the same Firebase project as Android, register TWO iOS apps with the
  exact respective bundle IDs; download each GoogleService-Info.plist.
- Create an Apple Push Notifications authentication key (p8) and configure
  Firebase Cloud Messaging with the Apple Key ID and Team ID.
- Create two App Store Connect apps: "OneSpace QA" for com.onespace.onespace.qa
  (TestFlight only, never released) and "OneSpace" for com.onespace.onespace. If automated upload is required, create an App Store Connect API
  key for the publisher account.
- In Supabase Auth redirect allowlists add the QA and production callbacks
  for their matching backend projects. Test email verification and recovery.
  OneSpace uses email sign-in only: Google and Apple sign-in are not allowed
  (Amr, 21 November 2026), so do not add Sign in with Apple.

### GitHub repository secrets (Actions)

| Secret name | Purpose |
|---|---|
| IOS_GOOGLE_SERVICE_INFO_QA_BASE64 | QA iOS Firebase registration (required for signed QA) |
| IOS_GOOGLE_SERVICE_INFO_PROD_BASE64 | Required production iOS Firebase registration |
| IOS_DISTRIBUTION_CERTIFICATE_P12_BASE64 | Distribution certificate and private key |
| IOS_DISTRIBUTION_CERTIFICATE_PASSWORD | p12 password |
| IOS_APPSTORE_PROVISIONING_PROFILE_BASE64 | App Store profile for production host app |
| IOS_SHARE_EXTENSION_PROVISIONING_PROFILE_BASE64 | App Store profile for production Share Extension |
| IOS_APPSTORE_PROVISIONING_PROFILE_QA_BASE64 | App Store profile for the QA host app (com.onespace.onespace.qa) |
| IOS_SHARE_EXTENSION_PROVISIONING_PROFILE_QA_BASE64 | App Store profile for the QA Share Extension |
| APPLE_TEAM_ID | Apple developer team |
| ASC_KEY_ID | App Store Connect upload key identifier |
| ASC_ISSUER_ID | App Store Connect API issuer |
| ASC_KEY_P8_BASE64 | App Store Connect upload key; required only when uploading |

Encode private files locally on your computer. Never commit signing keys,
service-account credentials or private keys into source control, nor paste
them into a chat. Store GitHub Actions secrets in the repository settings.

## Invitation Universal Links

Runner.entitlements requests `applinks:onespace.live`. The app already
accepts https://onespace.live/qa-invite/ (QA) and /app-invite/ (Production)
and rejects links for the other environment. To make the link open the app
directly instead of the web page, the website (onespace-app repository) must
publish `/.well-known/apple-app-site-association` once the Apple Team ID is
known:

    {"applinks":{"details":[
      {"appIDs":["TEAMID.com.onespace.onespace.qa"],
       "components":[{"/":"/qa-invite/*"}]},
      {"appIDs":["TEAMID.com.onespace.onespace"],
       "components":[{"/":"/app-invite/*"}]}]}}

Until then, invitations still work through the web page's "Open in OneSpace"
button and manual code entry.

## Real-device launch acceptance

- [ ] Sign-up, account pairing, recovery, biometric lock and account deletion
      work on a signed iPhone build.
- [ ] Invitations: email link, web page "Open in OneSpace", and manual code
      entry each reach the right (QA or Production) app.
- [ ] Private/shared ownership and lifecycle: leave, remove and delete a
      space, and the 7-day account deletion with cancel.
- [ ] Share Extension from Safari, Photos and Files, including cancel.
- [ ] iPad layout (the app is built for iPhone and iPad).
- [ ] Partner A on Android and Partner B on iPhone can create, edit, see,
      acknowledge and delete shared objects; private objects never cross.
- [ ] Mixed-platform notifications work in foreground/background/locked
      states, while signed out, and after denying permission. Navigation
      stays behind the session lock when applicable.
- [ ] Photos, voice messages, PDFs and data exports work on both sides;
      private storage access and cleanup are verified.
- [ ] Calendar, Contacts, Files and Photos access, and permission denial or
      cancellation, behave correctly on iPhone.
- [ ] English, Arabic and RTL screens, all themes, dynamic type, smaller
      devices, and both living arrangements have visual acceptance.
- [ ] App Store privacy disclosures, support/contact and privacy policy,
      screenshots, age rating, review account and account-deletion path
      match the shipped product.
- [ ] Founding membership and any in-app paid features comply with App Store
      review/purchase rules before taking public orders.
- [ ] Production data remains separate from QA; no signing secrets, debug
      diagnostics or private files enter public releases.

## Remaining engineering

- Native iOS sharing is now implemented in source with a separate app-extension
  target and private App Group inbox. It accepts one link/text item or one
  photo/PDF up to 10 MB, and keeps at most 20 pending items. There is no
  automatic upload or partner sharing. The person opens OneSpace and
  explicitly saves or sorts the received item. App Group registration,
  signing, and physical testing of the iOS share sheet are still pending.
  Test Safari, Photos, Files, denied access, cancellation, and both QA and
  production inbox isolation before releasing.
- Signed iOS QA uses the same TestFlight workflow with environment=qa and
  the QA profiles listed above.
- Lifecycle parity (leave/remove/delete space, 7-day account deletion,
  48-hour invitations) is shared Dart code with no iOS-specific native code,
  but must be exercised on a signed iPhone build.
- A verified production IPA, TestFlight install and real iPhone acceptance
  remain blocked on Apple credentials and physical testing.
- Voice app-icon shortcut is intentionally disabled pending voice QA.

The goal is feature-parity plus verified signing, not an untested claim
that the iOS app is ready for public App Store download.

## Source-only verification

The GitHub Actions workflow `ios-preflight.yml` runs on a Linux runner for
changes to iOS code, and verifies identity rules, the native Share Extension
project wiring, signed-IPA manifests, Dart share-intake logic, and calendar
rules. These checks do not replace Xcode compilation, signing, or iPhone UAT.
