# OneSpace QA — Private Data Migration, Archive and Separation Implementation (2026-11-19)

**Environment:** QA Supabase project `ugwrpeduzyzrujkizqfo`; Android application branch `qa/lifecycle-first-slice-20261119`.  
**Scope:** Additive QA-only migration; no destructive operation performed against real QA records, users, or Storage.

## Live QA inventory verified
| Inventory item | Result |
| --- | ---: |
| Existing relationship spaces | 3 |
| Existing space memberships | 5 |
| Source tables with direct `space_id` cascading foreign key | 33 |
| Explicitly private primary source records | 10 |
| Account-owned personal days off | 1 |
| Preserved Personal Vault primary records | **11** |
| Preserved private-parent owned dependent records | **18** |
| Migrated source table families with visibility+owner fields | 14 |
| Trigger mirrors including personal day and private descendants | 19 |
| Private source-record content/owner/visibility mismatches | **0** |
| Storage objects (five media buckets) | **59** |
| Database-to-storage path matches | **59 / 59** |
| Missing Storage paths | **0** |
| Unclassified media | **0** |
| Current media classified shared | **59** |
| Current media classified private | **0** |
| Archive objects ready | **0** |

## Implemented in QA
1. `0146_qa_personal_vault_shadow_migration.sql`: Add account-owned `personal_vault_records`, original `visibility`, source identifiers and full source snapshots. Existing tables remain canonical for now. `SECURITY DEFINER` mirror triggers for 14 typed source tables track new private records/updates and mark formerly-private records non-restorable when visibility turns shared. Authenticated clients cannot query or overwrite raw shadow snapshots.
2. `0147_qa_personal_vault_dependents.sql`: Personal-day protection and child snapshots for owner-authored private occasion steps, budget items and proposals, plus owner-specific reminder recipient records. Do not sweep in other partner's private children.
3. `0148_qa_personal_vault_status.sql`: User-scoped, count-only private-vault readiness report for My Space.
4. `0149_qa_space_media_inventory.sql`: Index all six known media reference types (memory photos, note images, trip documents, activity comment voice, activity-component images and voice). All 59 Storage objects are matched, with original parent visibility preserved. **Actual bytes and encrypted archive integrity are not yet verified.**
5. My Space > Check separation readiness now shows each signed-in member's protected primary/private-dependent record counts. No private payload exposed.
6. `SpaceLifecyclePolicy` and tests encode B Leaves / A Removes B / A Deletes Space / A Deletes Account / B Deletes Account, with continuous owner experience and shared space retirement.
7. Previously implemented secure temporary archive bucket, 30-day retention, user-initiated verified external download acknowledgement, app-private local copy and archive-only janitor remain intact.

## Explicit safeguards still active
- No Leave, Remove partner, Delete space or Delete account operations are enabled in QA. The old QA account deletion flow is disabled.
- The shared data still lives in original space tables. Do not delete any `spaces` row: 33 cascading foreign keys can erase private data and related objects.
- No media file was uploaded, copied, exported, purged, or deleted by the inventory migration.
- Personal Vault snapshots are NOT yet the fully normalized final app data model; original screens continue to use legacy tables. The next app cutover must preserve ownership and actual attachment relationships.
- No false claims about archive readiness. Current archive table has zero ready exports.
- No production code, production database, or production mobile app deployments were made in this migration.

## What still must be implemented before enabling lifecycle
1. Durable asynchronous export job that serializes **all authorized shared objects and dependent rows**, each partner's private records/children, and all actual media bytes, without including the other partner's private information.
2. Portable AES-GCM encryption, authenticated per-recipient archives, secure recovery-key strategy, integrity checks and manifest signing. Work across device loss/reinstall/account deletion.
3. Verified app-private auto copy (not a server-deletion trigger), user-deliberate external download and 30-day expiry; reliable email notifications and progress/retries.
4. Private-record cutover from legacy `space_id` foreign keys; link detachment/inert historical references, storage ownership and cross-space RLS enforcement.
5. Transactional, idempotent owner-continuity retirement/clean-space creation, B leave, A remove, explicit A Delete Space, and higher-level account-deletion cascading workflow. Never delete original shared media until both partners' authorized archives are verified.
6. Real Android and iOS restoration validation: private-only import, owner account match, duplicate-safe merge, progress bar, no old shared content reappears.
7. QA destructive scenario tests on **synthetic/disposable** accounts, real representative media, app reinstall, offline partner, expired archive and failure retries.
8. Re-enable QA deletion actions only when safety preflight and recovered archive tests are green, not when records are merely copied into vault metadata.

## SMTP
The real password-reset sender is controlled by Supabase Auth custom SMTP settings, not the branded invitation Edge Function. User must configure QA project's Auth SMTP with a verified Resend domain, from `OneSpace <support@onespace.live>`, host `smtp.resend.com`, port 465 (SSL/TLS), username `resend`, password a private Resend API key; then apply the branded Supabase email template in `supabase/email-templates/password_recovery.html` and test. Do not paste key into chat or GitHub. Production SMTP remains untouched.

## QA release
The newest source also includes previous password validation/Cancel, resend confirmation, Today CTA cleanup, QA-only `/qa-invite/` Android App Link, and branded invitation landing fallback. Build only `onespace.qa` after Flutter analyze/test; do not deploy to Production.

## Resumption gate
Read this document and `docs/ONESPACE_PAIRING_SEPARATION_ARCHIVE_RESTORE_DECISIONS_2026-11-19.md` before modifying lifecycle RLS or enabling deletion. The **explicit user-initiated external download** (verified after physical write) is the only early archive cleanup trigger; app-private automatic copies never trigger deletion.
