# OneSpace QA Lifecycle Milestone Board — 20 November 2026

## Approved product rules (do not reinterpret)
- Official tagline: **Two of Us. One Space**.
- Founder authorizes deleting historical QA records if needed for a **database ownership redesign**. No Production data changes.
- Archive **AND restore** must preserve structured private/shared content. **Exclude uploaded documents, photos, audio/video and other media**, including file pointers. Tell users clearly those excluded files are not recoverable from the archive.
- Private structured records belong to each person across relationships. Old shared history must never be loaded into a new partner's space.
- Leaving/removing a partner: the original owner continues in a clean new relationship boundary; partner unpaired. Deleting the space: both unpaired. Account deletion: separate seven-day grace-period workflow.
- Keep all destructive actions disabled until real end-to-end private/shared recovery and privacy checks succeed.

## Milestone 0 — app and invitation
- [x] QA 468 published with trusted QA signing certificate and corrected app/invitation source.
- [x] QA backend invitation regression rerun on 20 Nov: latest verified recipient, replaced-code resolution, accept/join, duplicate join and anonymous denial PASS (transaction rollback). This is **backend only**.
- [ ] New-user and existing-user latest-invitation flows verified on both Android phones.
- [ ] Hosted Supabase signup/reset emails verified in actual delivered messages. GitHub HTML files do not automatically update hosted Auth templates.

## Milestone 1 — structural ownership (QA backend migrations deployed)
- [x] Migration 0159: user-owned private snapshots exclude nested media keys/data URIs/Storage pointers, reject cross-space private authors, and invalidate snapshots on visibility/owner changes.
- [x] Migration 0160: authenticated private/shared **root preview** has sender/member scope, cannot see partner-private rows, and explicitly reports not complete or restorable.
- [x] Migration 0161: moving private dependent children to another parent/owner invalidates stale relationships; personal-days-off ownership verified.
- [x] Migration 0162: public lifecycle readiness and role status now report **structured-only**, excluding media/documents, without exposing partner-private counts or enabling separation.
- [x] Migration 0163: embedded media URLs are redacted without deleting surrounding written notes or captions.
- [x] Rollback-only database tests pass, with no changes to real users, memberships or stored records.
- [x] App/archive text now reflects structured-only archive policy and correct external download meaning (source branch; not yet installed).
- [x] QA migrations 0167–0168 now mirror private trip flight options, itinerary items and messages into owner-scoped Personal Vault child snapshots, with media sanitization and visibility/delete tombstones. The transactional author-isolation and re-private backfill regression passes; synthetic fixture rows rolled back.
- [x] QA 0171–0172: owner-private task checklist items and per-user completion checks are now mirrored with tombstones on deletion, shared/private transition resync and partner-authorship denial (rollback regression PASSED).
- [x] QA 0173: explicitly classified both task checklist child types after ownership tests: archive catalog **43/69 approved; 26 pending**.
- [x] QA 0174: read-only owner-only private checklist package preview includes task, items, checks and deterministic SHA-256; partner denial, tampering and partner-authored shared-history conflict fail closed (rollback regression PASSED). Not encrypted or restorable.
- [x] QA 0175: reviewed and excluded transient `activity_attention_snoozes` and `scrapbook_invites` operational state, preventing old snoozes and obsolete collaboration permissions from restoring into a new relationship. Regression passed. **45/69 approved, 24 pending (4 root, 20 dependent)**.
- [x] QA 0181: classified shared-experience **comments and revision history** as shared-only, with author-only access to archived comments, removal of reply pointers to hidden comments, sanitized text-preserving revision snapshots, per-recipient deterministic SHA-256, and outsider/lineage checks. Transactional two-member regression **PASS**. Coverage is now **47/69 approved, 22 pending (4 roots + 18 dependents)**; shared history still reference-only and not restorable.
- [ ] Personal Vault remains a shadow of the space-linked source tables, not canonical cutover.
- [ ] Roughly 35 related FK tables, system/shared-only types and multi-parent associations require complete ownership classification.

## QA 0176 — archive download hardening (verified)
- [x] QA `space_archives.ready_archives_complete` now **requires `encrypted_bytes_verified=true`** in ready/purge states. A rollback regression confirms unverified metadata is rejected and verified metadata passes.
- [x] `onespace-download-archive` Edge Function **version 2 active in QA**: checks verified-bytes flag and positive registry size, rejects Storage size mismatches when Content-Length is provided; JWT verification stays enabled.
- [ ] This does not produce any encrypted archives. Zero ready archives exist; live successful-file-download and cryptographic readback still require a real archive generator and test fixture.

## QA archive downloader v3 — live ciphertext integrity (verified)
- [x] QA archive download function **v3 active**, JWT verification enabled. It validates the actual encrypted Storage object SHA-256 against the verified registry hash **before returning any bytes**, not just the file size.
- [x] Bounded streaming read (maximum 50 MiB and cannot exceed verified byte count), rejects truncated, oversized, same-sized tampered, other-owner or unverified archive objects.
- [x] GitHub workflow `qa-archive-ciphertext-integrity.yml` ran successfully (run 44628511213), exercising the actual Edge handler with mocked Auth, PostgREST and Storage.
- [ ] This is a mock-backed handler test, not a live encrypted archive readback; archive generation/restore remain incomplete.

## QA-only portable encryption proof (no archive issuance)
- [x] Source-only `structured_archive_crypto.mjs` prototype: AES-256-GCM authenticated encryption, independent random salt/IV, PBKDF2-HMAC-SHA256 600,000 rounds, authenticated recipient identity and approved structured-only private trip/checklist preview schemas.
- [x] Strict media pointer sanitization guard, size/depth limits and identity validation; rejects wrong passphrase, tampering, changed KDF parameters and cross-account envelope access.
- [x] Node 22 QA crypto roundtrip/tamper tests passed in GitHub Actions run `44628764813`, alongside downloader regression tests, **without APK generation**.
- [ ] Prototype is not wired to a verified server-side archive issuer, durable encrypted Storage registry, app-private download or actual restoration. User-supplied passphrases alone cannot prove trusted server origin. Shared history remains reference-only and unimplemented.

## QA 0179–0180 — encrypted private-preview staging (not lifecycle archives)
- [x] QA migration **0179**: authenticated, owner-checked private task/trip package RPC; separate `qa_structured_preview_staging` registry with authenticated owner-only RLS, service-only inserts/updates, 5-per-account/24h rate limit, `is_verified_archive=false`, `can_restore=false`, `safe_to_separate=false` constraints. Rollback SQL test **PASS**.
- [x] QA migration **0180**: service-only due/finish cleanup RPCs for 24-hour preview Storage expiry. Rollback SQL regression **PASS**. Existing 30-day lifecycle archive registry is separate and unchanged.
- [x] Edge Function `onespace-qa-structured-preview` **v1 deployed to QA** with JWT verification and a QA-project hostname guard: owner-JWT read, AES-GCM passphrase encryption, private Storage upload, server-side readback SHA-256 verification, staging finalize, owner-only verified download and compensating cleanup.
- [ ] Actual authenticated live QA-account issuance/download and independently decrypted file acceptance still required. Mock-backed GitHub end-to-end tests validate code paths, not live Auth + Storage.
- [x] QA archive janitor **v2 ACTIVE**, still guarded by the existing cron secret; existing hourly `onespace-archive-janitor` scheduled at minute 37. Its new 24-hour preview cleanup uses Storage API and service-only registry RPCs; the original 30-day archive cleanup remains independent.
- [x] GitHub Action run `44630428012` completed its test step: **33 tests passed, 0 failed** across downloadable ciphertext verification, AES-GCM roundtrip, encrypted staging handler and janitor. Mock-backed Storage E2E only, not a live authenticated user run.
- [ ] **Not a full archive**: limited to one owner-private trip or checklist package at a time. The full 69-type structured archive and authorized restore remain incomplete; preview files never count toward lifecycle safety gates.

## QA 0182–0186 — substantial structured-history coverage (deployed and regression-tested)
- [x] QA **0182**: `scrapbook_pages`, `trip_revisions`, `saved_contact_revisions` approved with parent visibility, author/editor lineage, recursive media stripping, shared-private conflict denial and deterministic SHA-256. Rollback test PASS.
- [x] QA **0183**: all **six activity dependents** (`activity_components`, `activity_comments`, `activity_component_reactions`, `activity_decisions`, `activity_component_revisions`, `activity_revisions`) approved and packaged into owner/member-scoped structured preview; old shared collaborator history is rejected if activity becomes private. Rollback test PASS.
- [x] QA **0184**: `couple_letters` and `couple_letter_reads` approved with **author-private drafts and future-open dates**. Receiver sees sent letters only once eligible. Hidden reply references and unauthorized/invalid receipts cannot leak. Rollback test PASS.
- [x] QA **0185**: `place_visits` approved, inherited from `places` visibility; written captions preserved, links to old private memories and trips removed; cross-space and partner-to-private conflicts rejected. Rollback test PASS.
- [x] QA **0186**: `partner_checkin_acknowledgements` approved as old shared reference-only content, restricted to original sender/recipient, responded check-ins and valid sender-only receipts. Rollback test PASS.
- **Current QA catalog: 60 of 69 classified; 9 pending (2 roots, 7 dependents).** This is **classification + read-only preview only**, not a full source-of-truth archive, encrypted downloadable bundle, ID-remapping private restore, or authorization for deletion/separation.

## QA 0187–0194 — last nine archive types classified; safety gate deliberately CLOSED
- [x] **0187**: `reminder_actions` and `reminder_recipients` preserve written outcome notes with owner-vs-original-pair restrictions. Transient snooze/next-notification fields are explicitly stripped. Two-account regression PASS.
- [x] **0188–0189**: four occasion descendants (`occasion_budget_items`, `occasion_budget_log`, `occasion_plan_revisions`, `occasion_proposal_items`) serialize written budget/proposal history with strict same-plan and same-space validation, private author lineage and sanitized audit snapshots. Legitimate NULL system-audit actors allowed; non-null foreign actors denied. Two-account and cross-plan regression PASS.
- [x] **0190–0191**: `note_references` and `item_links` accept only existing same-space endpoints visible to the recipient; private endpoints never leak to the other partner. The PL/pgSQL dynamic-lookup guard was corrected and cross-space/restricted-link regression PASS.
- [x] **0192**: `record_action_history` (last type) supports **all 15 explicitly listed record kinds**, including author-only archived comments and pair-scoped check-in requests; missing parents or unauthorized audit actors fail closed. Transactional regression PASS.
- [x] **0193**: catalog status correctly separates **69/69 policy classification complete** from **encrypted_portable_archive_complete=false**, **trusted_private_restore_complete=false**, **source_of_truth_cutover_complete=false**, **safe_to_archive=false**, **safe_to_separate=false**. Simulated future table regression PASS.
- [x] **0194**: shared link/audit targets must have source creators belonging to the original active pair; test of outsider-authored source rejected and rolled back. No Production data touched.
- [ ] **Next major P0:** implement fully enumerated content manifest, trusted encrypted archive issuance, actual verified download and recipient decryption, then authorized private restore to an independent new space with idempotent ID remapping. Shared history stays separate/reference-only. No leave/remove/delete until this succeeds on both phones.

## QA restore dry-run — explicit remapping, no writes (source-only)
- [x] `qa_private_restore_dry_run.mjs` takes an authenticated/decrypted owner-private trip/checklist preview, checks exact owner and source-space IDs and requires a distinct destination space, validates complete child table sets, row counts, original parent references and per-child authorship. Rejects orphan checklist checks, duplicate source IDs, shared/foreign-owned data, embedded media or future unreviewed fields.
- [x] Generates fresh random UUIDs for root/children and remaps task checklist checks to newly mapped checklist items. Preserves written titles, notes, completion and travel details, but drops old partner assignment, migrated-list, traveler and external trip navigation IDs.
- [x] Performs a passphrase-protected AES-GCM decrypt → structural validation → ID remapping **without ever writing to Postgres or Storage**. All results assert `is_verified_archive=false`, `can_write=false`, `can_restore=false`, `safe_to_separate=false`.
- [ ] Still missing: full 69-type manifest, server-issued archive authenticity, checked ciphertext readback against a real QA file, authenticated target-space ownership, server transactional restore, duplicate/replay idempotence, shared reference-only history and two-device QA acceptance.

## Milestone 2 — durable structured archive and restoration (NOT COMPLETE)
- [x] Migration 0164: 69 root/child table types inventoried and the archive policy is fail-closed for future missing tables. **69 approved, zero pending; 4 known media types excluded.**
- [x] One synthetic new root plus child correctly made archive coverage incomplete and were rolled back.
- [x] Migration 0165: five RLS-verified shared roots classified; Love Letters drafts and sealed until-open dates explicitly remain blocked.
- [x] **All 69 of 69 table types classified** after QA 0187–0192, including the nine complex reminder/budget/polymorphic/audit types. Any future unregistered table still fails closed. This is privacy classification, **not verified encrypted archival, restoration, or safe separation**.
- [ ] Capture every supported structured root and dependent with manifest schema, privacy lineage, deterministic ordering, integrity and media-free sanitization. Three approved private trip-child types now have verified vault snapshots, but these are not yet downloadable archives.
- [x] QA migration 0170: stronger structured-only sanitizer removes scrapbook photo_N_id/image_N_id pointers, named document/file identifiers and attachment metadata. QA 0170 plus 0163, 0159 and 0169 regressions pass; zero extant restorable QA vault snapshots require backfill. Media/document uploads remain excluded.
- [x] QA migration 0169: owner-only nested structured trip package preview (trip + flight options + itinerary items + messages) with deterministic SHA-256 integrity checksum, parent-vault equality, media sanitization, child cap and member privacy checks. Transactional regression passed for partner denial, scope transitions, hash reproducibility and corrupt-vault failure. **Preview only; not encrypted or restorable.**
- [ ] Portable encrypted archive download, durable server-held copy and retention policy; downloaded file is the external copy.
- [ ] Prove authorized **private** restore into a new relationship with ID/FK remapping and deduplication; shared-history archive is reference-only.
- [ ] No incomplete preview may count as a verified archive or authorize a destructive lifecycle action.

## Milestone 3 — actual separation (NOT COMPLETE, hard-blocked)
- [ ] Partner leaves; owner removes partner; owner deletes space; both accounts remain private and correct.
- [ ] Safe Storage API cleanup of excluded media; verify no old shared references can be accessed by a new partner.
- [ ] Seven-day account-deletion grace period, cancellation, session revocation, partner preservation, verified deletion.

## QA security: export recipient-scope leak closed
- [x] QA 0177: fixed `SECURITY DEFINER export_my_data()` to export gesture templates by creator, and private gesture schedules by sender, **not the intended recipient**. The owner's own unsent drafts are now included without exposing them to the partner.
- [x] All general JSON-export rows and profile now use media-free structured sanitization, preserving written notes while excluding storage pointers/embedded uploads.
- [x] Transactional two-member regression passed: both own drafts export; neither partner sees the other's unsent content; anonymous export denied; image data removed and prose retained. No synthetic data persisted.
- [ ] Audit other privileged functions and arbitrary future export table types; this focused fix does not constitute comprehensive security sign-off.

## QA 0178 — fail-closed JSON export schema (verified)
- [x] The `SECURITY DEFINER export_my_data()` now uses a **fixed 63-table/column ownership allowlist** instead of dynamically discovering future `user_id`, `recipient_id` or other ownership columns. Gesture templates remain creator-only and schedules sender-only.
- [x] Regression added an unreviewed `user_id` table and a new `recipient_id` column to Notes inside a rollback-only transaction. Neither widened the caller's exported data, while their own note still exported.
- [x] Five regressions passed: new-table/column isolation, private gesture scope, two-account note export, archive catalog fail-closed, and lifecycle public-contract safeguards.
- [ ] Update the explicit JSON-export allowlist during future feature/schema reviews; automatic inclusion is intentionally forbidden.

## Milestone 4 — comprehensive QA acceptance and security (NOT COMPLETE)
- [ ] Two real devices and two-user lifecycle; nested-data archive and restore; error/rollback, offline partner, push, re-pairing.
- [x] QA `export_my_data()` two-partner privacy regression rerun and committed: each user exported their own private note, never the partner's; anonymous access denied; test rows rolled back.
- [ ] Complete authorization tests for remaining privileged Supabase functions and public endpoints. Latest QA advisor still flags 19 authenticated SECURITY DEFINER functions and 1 public support function; warnings are not by themselves exploit proof.
- [ ] Produce one signed QA build only after an integrated milestone; Production unchanged.

## Status reporting contract
- SQL tests passing means ONLY the named control was verified.
- GitHub merge is source change, not an installed APK or hosted Supabase template.
- Never claim full leave/remove/delete or archive/restore until an actual completed QA lifecycle test succeeds.
