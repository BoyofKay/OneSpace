# OneSpace

**Two lives. One space.**

A Flutter companion app for couples, whether living together or apart.

## Current foundation preview

- Email/password sign up, sign in, session restoration and sign out (Supabase Auth)
- Sign-up confirmation emails can be resent. Email confirmation and password recovery redirect into the preview app once the Supabase Auth callback is allowed (see [callback setup](docs/AUTH_CALLBACK_SETUP.md)); email delivery follows Supabase project limits
- Personal profiles: display names, per-person language preference, signed-in password change
- Secure creation of one shared space per account, limited to two members
- High-entropy invitation code, expires after 48 hours, one-time acceptance, invitation replacement revokes old codes
- Eight Supabase tables: `profiles`, `spaces`, `space_members`, `space_invitations`, `tasks`, `lists`, `list_items`, and `notes`
- Every exposed table has RLS; private tasks can be read/updated only by their creator, shared tasks only by space members, and assignment is restricted to space members.
- **Persistent tasks** with real-time updates, priorities, optional target dates, editing and open/completed/cancelled states. Tasks may be **Shared** (both members) or **Private** (creator only), and shared tasks may be assigned to either partner.
- Task visibility is immutable after creation to avoid stale realtime data exposure. Cancelled tasks stay in history (hard delete is not granted to application accounts).
- Home provides RLS-filtered task totals and counts of active shopping lists, checklists, and notes, with quick links to each module.
- **Shopping & checklists:** realtime shared/private lists, quantity/unit details, editable items, check-off, recoverable removal, archive/restore lists and bulk clear completed items.
- **Collaborative notes:** realtime shared/private notes, rich plain-text notes up to 30,000 characters, pinning, archive/restore, and conflict detection to prevent stale edits overwriting a partner's newer text.
- English and Arabic RTL are configured and core screens localized; some secondary copy and localized date formatting still require QA.
- Recent-email selection and native Samsung Pass/Google autofill for switching accounts; opt-in device fingerprint/PIN unlock for a saved session. No passwords or custom app PINs are saved by OneSpace.
- Signed-out password-recovery and reset-password screens are implemented; the user configured the preview callback but **end-to-end email and device testing** is still required. Memories, calendar, account deletion and full Arabic QA are future milestones.

## Install a standalone Android APK

Each successful push build publishes a GitHub pre-release with a direct `OneSpace-preview-*.apk` file on [GitHub Releases](../../releases). There is no ZIP to extract.

Preview APKs are now signed with a **fixed, non-secret development-only debug key** stored as a base64 file under `tools/dev-signing/`. This key must **never** be used for production distribution. It gives new preview builds a consistent signature so they can be installed over earlier previews (when Android build numbers increase).

**Important one-time transition:** The preview Android application ID is `com.onespace.onespace.preview`, distinct from the original Flutter sample's `com.onespace.onespace`. The first preview with the new package ID installs as a *separate app*. Subsequent previews use the same package ID and debug signing key for updates. A future production app will have its own application ID and a securely stored production signing key.

These are **development previews**, not public/commercial releases. Avoid storing critical personal data until authentication, security, recovery and device-install tests have been completed.

## Database and security

Supabase project: `ugwrpeduzyzrujkizqfo`. Schema definitions are versioned in `supabase/schema/`. The Flutter app uses a **publishable** key, never an admin or service-role key.

Privileged pairing logic lives in a private schema behind public invoker-only RPCs. Transactional SQL tests verify pairing, privacy, rejected invitations and shared/private content. The remaining Supabase Auth security advisor warning is **leaked-password protection disabled**. This setting must be evaluated/configured before public release.

See [the shared-workspace acceptance checklist](docs/SHARED_WORKSPACE_ACCEPTANCE.md) for two-account verification scenarios.\n\n## Ordered milestones

1. **Foundation:** account creation, email confirmation, sign in, profile, secure pairing and direct APK previews
2. **Validate foundation:** configure [Supabase preview redirect](docs/AUTH_CALLBACK_SETUP.md); end-to-end test with two real test users, password reset and deep link return, stable CI verification and auth edge cases
3. **Shared data:** persistent synchronized tasks, shopping lists/checklists, and collaborative notes (initial implementations committed; Android device acceptance pending)
4. **Daily experiences:** calendar, occasions/milestones, reminders, notifications, memories and flexible sharing
5. **Production readiness:** English/Arabic RTL, privacy controls, account deletion, stable secret production signing, app store preparation

## Development

Flutter stable 3.50.0. Use `flutter pub get`, `flutter analyze`, and `flutter test`. The GitHub build refreshes the dependency lockfile when necessary, commits it to the repository, then checks `flutter pub get --enforce-lockfile` for reproducibility.
