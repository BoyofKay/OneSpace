# QA 451 — post-R84 security and release hardening

Require-Firebase-Config: true

Build OneSpace QA from current main using the normal verified QA workflow. Target run 451, if no intervening workflow dispatch occurs.
QA package: onespace.qa; QA Supabase backend. Do not publish or overwrite production data.

## Included since QA 450
- Current main incorporates post-R84 security changes: restricted Supabase intake operations, scrapbook membership enforcement, client-side anonymous error-report correction, and backup workflow fail-closed logic.
- No new mobile feature branch is merged beyond R84; iOS launch-readiness PR #65 is still draft and excluded.

## Release checks
- Flutter dependency lockfile, analysis, tests, Firebase QA configuration, APK test signing and package-label verification in GitHub Actions.
- Publish a single QA APK and install over existing OneSpace QA without deleting data.
- Real-device acceptance and security/backup recovery remain launch gates, not claims of completion.

## Next
- Verify successful QA artifact and its commit before requesting a matching signed Android production Play AAB.
- iOS QA and production require native macOS compile, signing and additional iOS PR #65 integration after passing its own checks.
