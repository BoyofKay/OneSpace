# OneSpace release discipline — one preview per completed iteration

## Source commits are not releases

The Android workflow **does not run on normal pushes to main**. It has two
explicit triggers:

1. A final-iteration commit that adds/updates release/READY_TO_BUILD.md.
2. A human-initiated workflow_dispatch from GitHub Actions.

Do not edit the release marker while developing. Complete all source changes,
SQL migrations, documentation, tests and code review first. Then update the
marker once. Build and publish the single resulting preview APK.

## Release acceptance gates

The single release workflow performs, in order:

- Checkout the exact release-triggering commit;
- Flutter 3.50 dependency resolution from the committed lockfile (must not
  modify or push that file during the release workflow);
- Flutter analyzer and automated tests;
- Optimized signed APK build using existing preview-only signing identity;
- App signature and com.onespace.onespace.preview package verification;
- Signed APK artifact retention;
- GitHub Release publication, and verification of the released asset.

Do not call a release published until the matching GitHub Release lists its
signed APK. Do not call it phone-tested until both accounts and real Android
devices have passed the acceptance checklist.

Build number 0.1.N is GitHub's run number, not the iteration identifier.
A failed release is reported explicitly; fix the cause and trigger one
replacement candidate instead of starting background builds per commit.
If only publication failed, prefer re-running the publish job over rebuilding.

This avoids development-triggered cancelled runs and protects GitHub Actions
minutes, release history and the user's phone-testing experience.
