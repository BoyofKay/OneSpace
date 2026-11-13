# OneSpace

**One Life. Two Places. One Space.**

A Flutter companion app for couples, whether living together or apart.

## Current navigation

**Today | Remember | Coordinate | Connect | World**

- **Today:** the couple's shared dashboard, relationship context, actionable attention, and unified next-seven-day agenda (including trip departures and itinerary stops).
- **Remember:** calendar, to-do list, notes, upcoming dues and upcoming events (via a single RLS-filtered summary).
- **Coordinate:** reusable Activities and contributions for shared research and decisions.
- **Connect:** check-ins, love gestures, letters, memories, and Shared Experiences (movies, shows, music, books and games).
- **World:** Trips & Journeys with shared/private plans, flights, stays, bookings, itinerary, conversation, revisions and countdowns. Saved contacts remain in Remember.

Previous development test content was cleared on 13 November 2026, while two existing login accounts, one shared space and partner memberships remained intact.

## Current foundation preview

- Email/password sign up, sign in, session restoration and sign out (Supabase Auth)
- Sign-up confirmation emails can be resent. Email confirmation and password recovery redirect into the preview app once the Supabase Auth callback is allowed (see [callback setup](docs/AUTH_CALLBACK_SETUP.md)); email delivery follows Supabase project limits
- Personal profiles: display names, per-person language preference, signed-in password change
- Secure creation of one shared space per account, limited to two members
- High-entropy invitation code, expires after 48 hours, one-time acceptance, invitation replacement revokes old codes
- RLS-protected Supabase tables for pairing, Remember, Coordinate, Connect and World; schemas are versioned under `supabase/schema/`.
- Every exposed app table has RLS. Shared objects are visible to the two current space members, while private objects remain creator-controlled unless explicitly granted **revocable view-only** access; tasks, lists, notes, calendar entries and memories all participate.
- **Persistent tasks** with real-time updates, priorities, optional target dates, editing and open/completed/cancelled states. Tasks may be **Shared** (both members) or **Private** (creator only), and shared tasks may be assigned to either partner.
- Task visibility is immutable after creation to avoid stale realtime data exposure. Cancelled tasks stay in history (hard delete is not granted to application accounts).
- Home uses a single **SECURITY INVOKER** database snapshot instead of multiple HTTP requests; displays RLS-filtered task, shopping, checklist, note, calendar and memory counts. The paired space ID is cached briefly in memory per account.
- **Shopping & checklists:** realtime shared/private lists, quantity/unit details, editable items, check-off, recoverable removal, archive/restore lists and bulk clear completed items.
- **Collaborative notes:** realtime shared/private plain-text notes up to 30,000 characters, pinning, archive/restore and stale-edit conflict checks.
- **Calendar and occasions:** month grid, private/shared dated events, yearly repeating celebrations and anniversaries, leap-day-safe countdowns, task target dates and archive/restore; day-based only (timed meetings, device reminders and push notifications are future features).
- **Memories:** secure, dated shared/private text journal, editing, pinning, archiving and revocable view-only sharing; photo/video attachments require dedicated Storage security work.
- English and Arabic RTL are configured and core screens localized; some secondary copy and localized date formatting still require QA.
- Recent-email selection and native Samsung Pass/Google autofill for switching accounts; opt-in device fingerprint/PIN unlock for a saved session. No passwords or custom app PINs are saved by OneSpace.
- Signed-out password-recovery and reset-password screens are implemented; the preview callback is configured but **end-to-end email and device testing** is still required. Account deletion, timed reminders, photo storage and full Arabic QA remain future milestones.
- **Performance investigation:** project hosted in Supabase Seoul (`ap-northeast-2`). Home now uses one RPC; other modules reuse the in-memory membership cache. Profile → App performance shows local startup/network timings without collecting email, passwords or activity content. Physical-device timings remain unverified.

## Install a standalone Android APK

**Normal source commits do not build an APK.** Only an explicit final iteration marker or authorized manual dispatch invokes the release workflow. A verified release publishes a `OneSpace-preview-*.apk` on [GitHub Releases](../../releases), subject to GitHub permissions and Actions quota. If publication fails, the signed APK may be available as a workflow artifact. See [release policy](docs/RELEASE_POLICY_ONE_APK_PER_ITERATION.md).

Preview APKs are now signed with a **fixed, non-secret development-only debug key** stored as a base64 file under `tools/dev-signing/`. This key must **never** be used for production distribution. It gives new preview builds a consistent signature so they can be installed over earlier previews (when Android build numbers increase).

**Important one-time transition:** The preview Android application ID is `com.onespace.onespace.preview`, distinct from the original Flutter sample's `com.onespace.onespace`. The first preview with the new package ID installs as a *separate app*. Subsequent previews use the same package ID and debug signing key for updates. A future production app will have its own application ID and a securely stored production signing key.

These are **development previews**, not public/commercial releases. Avoid storing critical personal data until authentication, security, recovery and device-install tests have been completed.

## Database and security

Supabase project: `ugwrpeduzyzrujkizqfo`. Schema definitions are versioned in `supabase/schema/`. The Flutter app uses a **publishable** key, never an admin or service-role key.

Privileged pairing logic lives in a private schema behind public invoker-only RPCs. Transactional SQL tests verify pairing, privacy, rejected invitations and shared/private content. The remaining Supabase Auth security advisor warning is **leaked-password protection disabled**. This setting must be evaluated/configured before public release.

See the [shared-workspace checklist](docs/SHARED_WORKSPACE_ACCEPTANCE.md) and
[Calendar, Memories and performance acceptance plan](docs/CALENDAR_MEMORIES_PERFORMANCE_QA.md)
for two-account verification scenarios.

## R14 source status (not a phone release)

The additive database migration for Trips & Journeys is deployed and the Flutter source is committed. The accounts, memberships and existing app data are retained. Flutter analysis, automated execution, signed APK release and real two-phone validation **have not been run for R14** because GitHub Actions usage must be conserved. The documented acceptance cases are in [R14 Trips & Journeys QA](docs/R14_TRIPS_JOURNEYS_QA.md).

## Ordered milestones

1. **Foundation:** account creation, email confirmation, sign in, profile, secure pairing and direct APK previews
2. **Validate foundation:** configure [Supabase preview redirect](docs/AUTH_CALLBACK_SETUP.md); end-to-end test with two real test users, password reset and deep link return, stable CI verification and auth edge cases
3. **Shared data:** persistent synchronized tasks, shopping lists/checklists, and collaborative notes (initial implementations committed; Android device acceptance pending)
4. **Daily experiences:** initial day-based calendar, occasions, countdowns and text Memories shipped in source; timed events, notifications, offline queue and photo/video Memories next
5. **Production readiness:** English/Arabic RTL, privacy controls, account deletion, stable secret production signing, app store preparation

## Development

Flutter stable 3.50.0. Use `flutter pub get`, `flutter analyze`, and `flutter test`. The GitHub build refreshes the dependency lockfile when necessary, commits it to the repository, then checks `flutter pub get --enforce-lockfile` for reproducibility.
