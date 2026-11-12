# OneSpace

**Two lives. One space.**

A Flutter companion app for couples, whether living together or apart.

## Foundation (current work)

- Supabase-backed individual account creation, email/password sign in, and session management
- Profile editing (display name and personal locale preference), signed-in password change and sign-out
- Profiles with independent language preference (English/Arabic ready at the data level)
- One private shared space per person, up to two members per space
- Invitation codes expire after 48 hours, can be revoked, and cannot be reused after acceptance
- Database Row Level Security (RLS) protects personal and shared records
- Plans & Tasks is currently a **local-only preview** and does not persist or synchronize data
- Memories is a placeholder. Password recovery while signed out, account deletion, and production-grade authentication testing are still outstanding.

## Download one APK file directly from GitHub Releases

Every push to `main` triggers the automated analysis, tests, and Android preview build. When the workflow succeeds, a versioned **pre-release** is published under [GitHub Releases](../../releases), with a directly downloadable `OneSpace-preview-*.apk` file. No artifact ZIP extraction is required.

**Preview-signing limitation:** Current builds use Android *debug* signing. Android version codes increment automatically with each GitHub run, but this does **not** solve signing mismatches. GitHub runners may create a different debug key for each build. This can prevent installing a new APK as an update over an older build. If that happens, uninstall the earlier preview and install the new one; this can delete data stored locally. We will establish a private, stable production keystore in GitHub Actions secrets before moving to user-data-sensitive update testing or public distribution. Do not use these previews for important data.

## Backend

Supabase project: `ugwrpeduzyzrujkizqfo`. Database schema is versioned in `supabase/schema/0001_foundation.sql`. The application includes only the **publishable** Supabase key, never an admin/service key.

## Roadmap

1. **Foundation:** auth, RLS, profiles, secure pairing, direct APK distribution
2. **Complete foundation:** password reset, email verification return flow, stable signed updates, authentication testing
3. **Shared data:** persistent and synchronized tasks, reminders, and lists
4. **Experience:** calendar, photos, memories, sharing, localization (English and Arabic RTL)
5. **Production:** privacy review, comprehensive tests, signing, store readiness

## Development

Flutter 3.50.0 (stable). Run `flutter pub get`, `flutter analyze` and `flutter test`.
