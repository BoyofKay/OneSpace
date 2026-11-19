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
- [ ] Personal Vault remains a shadow of the space-linked source tables, not canonical cutover.
- [ ] Roughly 35 related FK tables, system/shared-only types and multi-parent associations require complete ownership classification.

## Milestone 2 — durable structured archive and restoration (NOT COMPLETE)
- [x] Migration 0164: 69 root/child table types inventoried and the archive policy is fail-closed for future missing tables. 41 approved, 28 pending; 4 known media types excluded.
- [x] One synthetic new root plus child correctly made archive coverage incomplete and were rolled back.
- [x] Migration 0165: five RLS-verified shared roots classified; Love Letters drafts and sealed until-open dates explicitly remain blocked.
- [ ] Explicitly classify the remaining 4 root and 24 dependent types; see docs/QA_ARCHIVE_COVERAGE_CATALOG_20261120.md.
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

## Milestone 4 — comprehensive QA acceptance and security (NOT COMPLETE)
- [ ] Two real devices and two-user lifecycle; nested-data archive and restore; error/rollback, offline partner, push, re-pairing.
- [x] QA `export_my_data()` two-partner privacy regression rerun and committed: each user exported their own private note, never the partner's; anonymous access denied; test rows rolled back.
- [ ] Complete authorization tests for remaining privileged Supabase functions and public endpoints. Latest QA advisor still flags 19 authenticated SECURITY DEFINER functions and 1 public support function; warnings are not by themselves exploit proof.
- [ ] Produce one signed QA build only after an integrated milestone; Production unchanged.

## Status reporting contract
- SQL tests passing means ONLY the named control was verified.
- GitHub merge is source change, not an installed APK or hosted Supabase template.
- Never claim full leave/remove/delete or archive/restore until an actual completed QA lifecycle test succeeds.
