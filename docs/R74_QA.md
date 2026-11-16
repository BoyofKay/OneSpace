# R74 — QA checklist (APK 0.1.439)

## Before inviting the 2 couples
- [x] Each couple has a separate shared space (max 2 members, enforced by the database).
- [x] RLS prevents cross-couple access (tested with a simulated stranger: 0 rows, all writes and RPCs refused).
- [x] Push goes only to the current member's devices.
- [x] Uploaded files are private (all 7 buckets private; access through item rules).
- [x] Deleting an account: 7-day grace, then purge (cron onespace-account-purge); shared items stay with the partner.
- [ ] Error monitoring: client_errors table (automatic) — check it daily during the test.
- [ ] Backups: add the two GitHub secrets (docs/R74_SETUP.md §3) and run once.

## New in the app
1. Sign-up: the button needs the terms box; links open Terms of use and Privacy summary.
2. Existing account: first open shows "Before you start" once; Accept → app; Sign out works.
3. Sign-in screen bottom: Help / Contact us / Report a problem work without an account (email required; "I cannot sign in" topic). 4th message in an hour from the same email is refused.
4. Email confirmation / password-reset link opens the installed app (was broken in the APK).
5. Google / Apple buttons appear only after the provider is enabled in Supabase; complete a sign-in and land in the app (terms screen first time).
6. Me › Settings › Show in my phone calendar → allow → "Done — N items". Open Google/Samsung Calendar: a "OneSpace" calendar with events, trips (✈), occasions (🎁), special dates (❤). Turn off → calendar disappears.
7. Tablet (or phone in landscape on a big screen): the app sits in the middle at phone width.
