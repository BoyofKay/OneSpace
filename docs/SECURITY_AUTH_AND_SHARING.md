# OneSpace authentication, privacy and shared-content security review

Status: November 2026, development preview. This is a design and implementation
review, not a certification or penetration-test report.

## Threat model

- Two separately authenticated people share one space; either person may keep
  private data that the other is not entitled to see.
- Partners may own different physical phones, or may be testing two accounts on
  one phone.
- Shared content must not grant the recipient any editing access when the owner
  grants **view-only** access to a previously private item.
- A stolen, unlocked or unattended device must not expose existing content via
  an automatically restored app screen.
- A leaked access or refresh token can be used without going through an app
  lock screen: local app locking is NOT a substitute for backend session policy.

## Implemented safeguards

1. **Identity**: Supabase Auth controls password verification and token refresh.
   OneSpace stores no passwords, fingerprint images, biometric templates or
   custom numeric PIN. The app's recent-account list contains only emails.
2. **Device unlock**: local_auth 3.0.2 defaults to
   `authenticate(biometricOnly:false)`, permitting OS biometric recognition
   or fallback to device PIN, pattern or password. The phone decides which
   methods are offered. A damaged fingerprint reader does not require
   OneSpace to implement its own PIN system.
3. **App privacy timeout**: local lock after 5 minutes without UI interaction.
   Content is covered as soon as the app becomes inactive; returning after
   30 seconds away or after the idle threshold requires device-unlock or
   account-password verification. These are **local presentation controls**.
4. **Saved auth session**: Android Keystore-backed encrypted secure storage
   replaces plaintext shared_preferences for session persistence. A one-time
   migration only removes the old copy after verifying the encrypted copy.
   If secure storage is unavailable, the user may need to sign in again.
   Android application data backup is disabled.
5. **Independent devices**: switching or signing out uses local Supabase
   session scope, so it should not revoke the user's other phone's session.
6. **RLS**: a couple's shared content can be read by current members of that
   space. Private content is owner-only unless the owner explicitly grants
   view-only access to the current partner. Every object permission is
   enforced by Postgres, not merely by hiding Flutter buttons.
7. **Private sharing**: object_shares only exposes grants to their owner or
   recipient. A SECURITY DEFINER RPC verifies ownership, the object being
   private, current membership and the recipient before inserting/revoking
   a grant. Normal mobile clients cannot write to grants directly.
8. **Revocation**: a revoked grant immediately prevents fresh database reads.
   A partner may still possess information they already viewed or copied,
   and old on-screen views may require refresh. Revocation cannot erase
   screenshots or knowledge; do not promise otherwise.

## Different kinds of timeout

| Control | In this preview | Guarantee |
| --- | --- | --- |
| App idle privacy lock | 5 minutes | UI-only; no remote token revocation |
| Background privacy shield | Immediately on inactive/hidden | Hides Flutter content while backgrounded |
| Unlock after background | 30 seconds | UI-only |
| JWT expiration | Supabase configuration (verify in dashboard; typical 1 hour) | Signed JWT expires on server; refresh may continue |
| Absolute server session limit | Not configured or verified | Requires plan with session timeout support |
| Server inactivity termination | Not configured or verified | Requires plan with session timeout support |
| Forced sign-out everywhere | Not enabled by routine account switching | Use explicitly for account compromise/security action |

**Recommended for a public release**: plan-eligible server-side absolute
session lifetime (for example 30 days), backend inactivity timeout (for
example 7 days), short JWT life (normally default 1 hour), plus a
device-local 5-minute privacy lock. These are **proposed defaults**, not
settings already enabled. Consider the consequences for remote long-distance
partners and offline mobile use before enforcing remote session limits.

## Remaining security gates before public use

- [ ] Confirm both physical Android devices can use a system PIN when
      fingerprint is missing or broken (OS version/hardware dependent).
- [ ] Device-test 5-min idle, 30-sec background, notification switch,
      hardware Back, offline and cold-start session restoration.
- [ ] Test the existing session's one-time encrypted-storage migration and
      logout/relogin; verify old plaintext session key is removed.
- [ ] Verify recoverability when Android Keystore data is damaged or restored
      to a new phone; fall back to password sign-in without leaking tokens.
- [ ] Validate RLS with two users and a third outsider for all shared and
      private parent/child objects.
- [ ] Validate grant/revoke changes on two phones, including reopening a
      previously displayed view-only list/note and losing membership.
- [ ] Check Supabase Auth rate limiting, email confirmation, password policy,
      SMTP, leaked-password protection (plan-dependent), and sign-in audit
      logs in the project dashboard.
- [ ] Implement account unlinking, deletion, data retention/export and breach
      response. Never claim revocation removes copies already seen.
- [ ] Build a proper production signing setup, protect CI releases and
      enforce verified HTTPS deep links instead of preview custom schemes.
- [ ] Consider passkeys/MFA for high-sensitivity users after evaluating
      beta support and Android Digital Asset Links setup.
- [ ] Independent code review and privacy/security testing before listing
      this app publicly.

Supabase documentation: https://supabase.com/docs/guides/auth/sessions
Android local_auth: https://pub.dev/packages/local_auth
Encrypted-storage package: https://pub.dev/packages/flutter_secure_storage
