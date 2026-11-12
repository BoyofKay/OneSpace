# OneSpace

**Two lives. One space.**

OneSpace is a Flutter companion app for couples, designed for living together or across distances.

## Current development preview

- Home dashboard and four-tab navigation
- Plans screen: add, prioritize, filter, complete and delete tasks; optional target dates
- **Important:** Tasks currently exist in memory only and reset when the app is restarted. There is no authentication, storage, or partner synchronization yet.
- The invitation button is a placeholder and does not send invitations.

## Android preview builds

Every push to `main` triggers [Android development APK](../../actions/workflows/android-dev.yml) to run analysis, tests, and build a **debug APK**. If the workflow passes, download the `OneSpace-development-APK` artifact from that run.

**Debug APKs are for testing only.** GitHub-hosted runners can sign them with different debug keys, so installing a newer build over an older one may fail. Do not treat these as production releases. Permanent signing and versioned releases will be configured before distributing app updates.

## Roadmap

Next milestones: durable data persistence, individual authentication, secure partner pairing, shared workspace and permissions, synchronized tasks, internationalization (English/Arabic RTL), and release signing.

## Development

Requires Flutter 3.50.0 (stable). Run `flutter pub get`, `flutter analyze`, and `flutter test`.

