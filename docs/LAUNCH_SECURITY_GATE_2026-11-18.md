# OneSpace launch security, recovery and release gate — 18 Nov 2026

Status: PARTIALLY VERIFIED. This is an engineering audit, not a penetration-test certification.

## Separate environments
- QA: `ugwrpeduzyzrujkizqfo` (4 Auth users, 2 spaces at review)
- Production: `letcgxbnblohhfyeuigz` (0 Auth users, 0 spaces at review)
- User confirmed leaked-password protection enabled on both; connector does not expose the Auth configuration toggle.

## Database authorization
- QA: 8 cross-space RPC negative tests PASS, rolled back: `create_scrapbook`, `create_trip_preparation_checklist`, `invite_scrapbook_partner`, `remove_scrapbook_page`, `record_activity_decision`, `respond_to_reminder`, `save_occasion_proposal`, `respond_scrapbook_invite`.
- QA: 12 remaining signed-in privileged RPC safety probes PASS, rolled back: `accept_terms`, `cancel_account_deletion`, `demo_reset_space`, `disable_push_device`, `export_my_data`, `log_app_events`, `log_client_error`, `register_push_device`, `request_account_deletion`, `sealed_letters`, `set_how_we_live`, `submit_public_support`. The latter are scoped-operation/invalid-input tests, not 12 additional cross-space mutation tests.
- Security Advisor: QA and Production each still have 20 authenticated privileged-function WARN notices and 1 intentionally callable anonymous support-function WARN. These must not be dismissed solely to make the count zero.
- All 20 function names/argument signatures are present in both environments. Function definitions were byte-for-byte identical for 18; `log_client_error` and `submit_public_support` contain formatting/comment differences with matching security-relevant logic, owner and guards.
- Last change on both databases: migration `0140_security_scrapbook_current_membership.sql`, requiring current space membership for scrapbook invitations.
- 76/76 public tables in each project have RLS; all Storage buckets are private. Real-device and third-party penetration tests remain open.

## Public support abuse
- Website's `founder-join` and `site-contact` Edge Functions require server-verified Turnstile in QA and Production.
- Mobile pre-sign-in `submit_public_support` intentionally remains anonymously callable; database bounds inputs and limits global intake to 30/hour and 3/hour/email. Direct database RPC calls can bypass the website's Turnstile. This creates a residual quota-exhaustion risk.
- Pre-launch remediation: separate website and mobile intake with appropriate independent app/device verification, IP/device-level quotas and failure monitoring, while preserving help before sign-in. Do not revoke the RPC before mobile clients have moved.

## Backups and restoration
- 17 and 18 Nov GitHub QA backup workflow runs showed SUCCESS but their dump steps were SKIPPED and no encrypted artifacts existed. They are **not proof of backups**.
- The workflow now fails on missing `SUPABASE_DB_URL` or `BACKUP_PASSPHRASE`, and verifies that each encrypted dump can be decrypted into a valid gzip stream.
- **No successful GitHub encrypted backup artifact or restore has yet been demonstrated.** Configure the secrets and manually run the workflow. Never restore a test into QA or Production.
- Supabase Pro includes automatic daily database backups (usual 7-day retention), but availability for these two specific projects has not been independently inspected through the connector.
- Database backups only save Storage object metadata, not binary images, audio, or documents. At the audit: QA has 59 private stored objects; Production has 0. A separate secure binary-object backup and isolated restore drill are necessary.
- An actual restore acceptance test requires an isolated, separately billed Supabase clone or a correctly configured compatible staging system, plus a sampled protected Storage-object restore. It has NOT been performed.

## Sessions, deletion and export
- QA and Production each have an active daily account-purge Cron, plus events/client-error cleanup and push-delivery jobs. Active schedule does not prove successful end-to-end purge.
- QA account deletion and `export_my_data` were exercised in a rolled-back functional safety probe. No real account was deleted.
- `export_my_data` exports matching database records as JSON, not the underlying Storage file bytes or a partner's independently created shared items. Full portability requires a separate media-export workflow.
- Existing mobile code documents local OS biometric/PIN fallback, immediate background shield, 5-minute idle and 30-second return lock. Real-device verification and server-side maximum-session/inactivity settings remain outstanding.

## Android
- Previous Google Play workflow run `44064622211` succeeded and produced signed `OneSpace-Play-1.0.0-3` AAB (17 Nov).
- Fresh Production signed build requested by explicit marker `release/PRODUCTION_READY_TO_BUILD.md`, run `44353582051` (18 Nov). At time of this document, it is running analyzer/tests/build; no Play upload has occurred.
- Manual Play Console closed testing and actual phone tests are not completed by producing an AAB artifact.

## Command Center
- Production and QA mobile KPI aggregate queries executed successfully; Production empty account results are grounded, not copied from QA.
- False-zero inactivity windows fixed in merged PR #46. Insufficient refresh-token history now means unknown; CI passed. Merged source requires Cloudflare deployment.
- Production Founder-app aggregate attribution (confirmed email match, push-enabled proxy, paired app space) added in merged PR #47; read-only SQL and CI passed. Counts only leave Production. Still requires Cloudflare deployment.
- Firebase delivery reports use the delayed Android FCM Data API; no direct Firebase provider live verification or app analytics/Crashlytics integration was performed in this audit. Peak users per hour is NOT a concurrent-user metric.

## Do not close P0 until
1. Independently confirm Supabase automatic daily backup inventory for both environments and establish offsite encrypted backups.
2. Successfully decrypt and **restore** to an isolated target, including selected private Storage files.
3. Complete cross-user QA regression and real-device auth/biometrics/offline/notification tests.
4. Verify account deletion end to end on a disposable QA identity and validate data export completeness.
5. Complete signed Production AAB build, install/closed-track validation, pairing and Firebase delivery.
6. Verify server session policy, public support abuse controls and independent security review.
