# OneSpace QA — complete source recovery and safe space-lifecycle integration

Require-Firebase-Config: true

## This is a QA-only, single signed Android candidate

The source must contain the complete features from QA Release 461, the verified
password-recovery fix introduced in 462, and the QA lifecycle-preparation
integration. Do not build from any older divergent branch.

### Features that MUST remain
- Profile > My Space: original owner, invited partner and solo-user roles.
- Dedicated Change password screen, disabled Submit until valid, Cancel and reset email.
- Invite my partner: addressed invitations, QR/manual code and correct app-link routing.
- My Archives: app-private encrypted-copy caching and user-initiated external save
  of already verified server archives; do not claim any archives were generated.
- Personal Vault protected private-record infrastructure and privacy-aware related records.
- QA-only authenticated lifecycle staging APIs: Prepare removal, Prepare leaving,
  Prepare deletion, active-job status and cancellation before export.
- Accurate readiness audit: detect missing private/shared encrypted exports and
  refuse unsafe removal, deletion or account purging.
- Firebase push, core Today/Remember/Coordinate/Connect features, translations.

### Source gate
Check preserved feature fingerprints (exact R461 Git blobs) plus Flutter analyzer
and automated tests. See signed QA GitHub workflow and rollback-only SQL test
supabase/tests/qa_space_lifecycle_staging_regression.sql.

### QA build gate
- flutter pub get --enforce-lockfile, flutter analyze, flutter test.
- Build release Flutter QA flavor with `ONESPACE_ENV=qa`.
- Verify package `onespace.qa`, QA signing certificate and Firebase QA config.
- Preserve final signed APK artifact and publish one matching GitHub QA Release.
- The asset must be traceable to this exact release-triggering source commit.
- Do not deploy anything to Production, Google Play, App Store or TestFlight.

### Manual Android acceptance
1. Verify My Space, invitation, change password and archive screens remain.
2. Owner sees Prepare removal/Delete, invited partner sees Prepare leave.
3. Confirmation-only popup, stage a request, view pending status, cancel it.
4. Confirm no partner is removed and no account/space deleted: real transitions
   are deliberately blocked until verified encrypted archives are implemented.
5. Confirm two QA accounts still have the original pairing and privacy boundaries.
6. Verify recovery email opens Set a new password without an old dialog covering it.

## Important safety boundary
This candidate fixes the release regression and completes the **safe request,
authorization, and readiness cycle**, not the archive export/transition cycle.
Actual destructive lifecycle transitions remain fail-closed pending complete,
media-inclusive encrypted archives and separately validated restoration.
