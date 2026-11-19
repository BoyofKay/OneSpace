# OneSpace QA — corrective recovery after Release 462 source regression (2026-11-19)

Require-Firebase-Config: true

Build ONE signed, installable QA APK from this commit and this branch,
not from the divergent main source used by Release 462.

## Recovery source
- Base: verified feature-complete QA Release 461 (commit aa4cbc86056b5253b51e63e7dea59e4473046304).
- Keep the dedicated Change password page with validation, Cancel, and reset email.
- Keep Invite my partner, invitation QR/manual code, My Space, and My Archives.
- Keep personal-vault migration/lifecycle policy source and QA acceptance tests.
- Retain the Release 462 password recovery routing improvement:
  verified email callback brings the new-password form to the foreground;
  requesting reset from Change password closes that page gracefully;
  previous password works until the new password is successfully saved.
- Preserve native invitation/app-link handling, branded email sharing,
  language strings, and all other Release 461 features.

## QA only; safety limits
- Android package: onespace.qa
- Supabase QA project: ugwrpeduzyzrujkizqfo
- NO production/Play/App Store/TestFlight deployment.
- Existing QA users, spaces and memberships MUST NOT be reset.
- Space separation, archival transitions and account deletion remain
  safety-gated until encrypted export and privacy verification are complete.

## Release acceptance gates
- Verify Release 461 source ancestry and required feature files.
- flutter pub get --enforce-lockfile, analyzer and tests.
- Verify Firebase QA configuration, build release QA flavor,
  validate package name and signing certificate, retain signed APK artifact.
- Publish ONE corrected QA release only if all checks pass.

## Manual acceptance on Android
- Profile shows My Space and the dedicated Change password subpage.
- Invitation page, code/QR and My Archives remain visible.
- Password reset email navigation returns directly to the reset form,
  without an old dialog/page covering it.
- Verify both existing QA accounts, correct pairings and no data loss.
- Destructive actions are appropriately blocked until real encrypted
  private/shared archive and separation validations pass.

Do not merge obsolete PR #70 unmodified; its migration sequence conflicts
with the R461 baseline. Recovery PR #71 records the corrected source.
