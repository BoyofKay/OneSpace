# OneSpace Android production build — match QA 451 source (2026-11-18)

- Explicitly request a signed Google Play AAB from main after QA 451 source marker commit 68feb379e780eb2bcad953dc2060af57c22cfb2d.
- Application ID live.onespace.app; ONESPACE_ENV=production; production Supabase only.
- Production version name 1.0.0, with a new monotonically increasing build number set by GitHub Actions.
- Exact application source and dependency lockfile match QA 451; production flavor, signing key, Firebase configuration and backend remain distinct.
- Build must pass Flutter analyze and test, production Firebase registration, package/signature checks.
- Artifact only; NO deployment or Play Store publishing. Upload first to a closed testing track after QA and security acceptance.
- iOS production and QA compile verification is in a separate isolated macOS CI branch; this marker does not publish iOS.
- Unresolved launch gates: backup and restore, real-device testing, account deletion, session/security review.
