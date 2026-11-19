# OneSpace QA — safe lifecycle, archive privacy, and release source hardening (2026-11-19)

Require-Firebase-Config: true

Build ONE signed Android QA APK, package `onespace.qa` against QA Supabase
`ugwrpeduzyzrujkizqfo`. Do not deploy to Production, Play or TestFlight.

## Verified source
The `main` branch includes the feature-complete R461 restoration, R462
password-recovery navigation fix, and the merged QA hardening PR #73.
The release workflow must pass its recovered-main ancestor guard and check
required source files before building. Never publish from divergent branches.

## Included QA fixes
- My Space never calls QA-only lifecycle RPCs in Production.
- My Archives remains accessible for unpaired QA users and stays hidden in
  Production until the archive feature is implemented there.
- Read-only safety check reports archived-copy progress and schema coverage
  without disclosing the partner's private-record counts or raw table detail.
- JSON account-data export is accurately described as unencrypted and not
  containing media, and not equivalent to an encrypted separation archive.
- Internal QA audit covers 35 dependent tables, correctly follows occasion
  plan and task-checklist ownership, and flags invalid cross-space linkages.
- Account deletion remains blocked and now uses caller privileges only.
- CI source guard protects against another R462-type regression without
  prohibiting legitimate future UI changes.

## Required automated verification
- `flutter pub get --enforce-lockfile`
- `flutter analyze --no-fatal-infos` and `flutter test`
- QA Firebase configuration and Android QA flavor
- QA package name, known preview signing cert, signed APK artifact and
  GitHub release matching the exact build commit.

## Manual device acceptance after installing
1. Profile: My Space, My Archives and Change password screens appear.
2. Signed-in owner: prepare/cancel removal or space close (no real removal).
3. Signed-in invited partner: prepare/cancel leave (no real leave).
4. Solo account: owner actions shown correctly; My Archives remains reachable.
5. Check separation readiness. No partner-private counts or raw records leaked.
6. Verify correct invitation/QR/manual code, password recovery, Firebase push,
   both test phones, original accounts and pairings.
7. Confirm account/space deletion remains blocked while encrypted archive
   generator, external recovery and private-only restoration are incomplete.

No QA test users, spaces, memberships or storage files may be reset to
pass these checks. Production Supabase remains untouched.
