# OneSpace

**Two lives. One space.**

A Flutter companion app for couples, whether living together or apart.

## Current foundation preview

- Email/password sign up, sign in, session restoration and sign out (Supabase Auth)
- Sign-up confirmation emails can be resent; email delivery follows Supabase project limits
- Personal profiles: display names, per-person language preference, signed-in password change
- Secure creation of one shared space per account, limited to two members
- High-entropy invitation code, expires after 48 hours, one-time acceptance, invitation replacement revokes old codes
- Five Supabase tables: `profiles`, `spaces`, `space_members`, `space_invitations` and `tasks`
- Every exposed table has RLS; shared tasks can be read/updated only by members
- **Persistent shared tasks** with real-time updates, priorities, optional target dates and open/completed/cancelled states
- Cancelled tasks stay in history (hard delete is not granted to application accounts)
- Memories is currently a placeholder; Arabic RTL interface translation, account recovery while signed out, and account deletion are future milestones

## Install a standalone Android APK

Each successful push build publishes a GitHub pre-release with a direct `OneSpace-preview-*.apk` file on [GitHub Releases](../../releases). There is no ZIP to extract.

Preview APKs are now signed with a **fixed, non-secret development-only debug key** stored as a base64 file under `tools/dev-signing/`. This key must **never** be used for production distribution. It gives new preview builds a consistent signature so they can be installed over earlier previews (when Android build numbers increase).

**Important one-time transition:** The preview Android application ID is `com.onespace.onespace.preview`, distinct from the original Flutter sample's `com.onespace.onespace`. The first preview with the new package ID installs as a *separate app*. Subsequent previews use the same package ID and debug signing key for updates. A future production app will have its own application ID and a securely stored production signing key.

These are **development previews**, not public/commercial releases. Avoid storing critical personal data until authentication, security, recovery and device-install tests have been completed.

## Database and security

Supabase project: `ugwrpeduzyzrujkizqfo`. Schema definitions are versioned in `supabase/schema/`. The Flutter app uses a **publishable** key, never an admin or service-role key.

The Supabase advisor currently flags the three intentionally authenticated `SECURITY DEFINER` pairing RPCs, which each perform an authorization check. They require dedicated negative-path and concurrency tests before general availability. The tables have RLS and least-privilege grants.

## Ordered milestones

1. **Foundation:** account creation, email confirmation, sign in, profile, secure pairing and direct APK previews
2. **Validate foundation:** end-to-end test with two real test users, password reset and deep link return, stable CI verification and auth edge cases
3. **Shared data:** persistent synchronized tasks (initial implementation), reminders, shopping lists and notes
4. **Daily experiences:** calendar, dashboards, notifications and flexible sharing
5. **Production readiness:** English/Arabic RTL, privacy controls, account deletion, stable secret production signing, app store preparation

## Development

Flutter stable 3.50.0. Use `flutter pub get`, `flutter analyze`, and `flutter test`.
