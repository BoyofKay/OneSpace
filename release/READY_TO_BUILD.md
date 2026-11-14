# R25 — Configured Firebase Android Preview

This controlled Android preview is triggered after the project owner added the
GitHub Actions secret `ONESPACE_GOOGLE_SERVICES_JSON_BASE64`.

## Hard prerequisite
The build must decode the private GitHub Actions secret and verify that
`google-services.json` contains the Android client application ID
`com.onespace.onespace.preview`. **If the secret is missing, malformed, or
registered to another package, fail the build and publish no release.**

## Scope
- Carry over signed OneSpace preview v0.1.402 / R24, with no uninstall/reset.
- Activate Firebase client resources for the configured Android Firebase project
  through com.google.gms.google-services. No service account key enters the APK.
- Firebase Messaging token registration remains per user and per device.
- In-app notifications and all current features remain operational.
- Run full Flutter analysis and tests, native Android Gradle build,
  verify signing and unchanged `com.onespace.onespace.preview` application ID.
- Publish one signed tested APK if all checks pass.

## Not yet proven
- The Firebase Admin service account and the push-worker secret must be configured
  in Supabase Edge Function secrets.
- The scheduled push-worker job must be activated only after credentials are set.
- End-to-end push delivery still requires physical testing on two phones.
- An Android Google Services config is a client setting, not permission to send
  Firebase messages from Supabase. No private keys are stored in GitHub.

Upgrade safely over v0.1.402 and keep existing accounts and data.
