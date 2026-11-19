# QA backlog — next hard gates (19 November 2026)

**Scope:** QA Supabase `ugwrpeduzyzrujkizqfo`; no Production migration or destructive action.

## Verified repairs
- QA source restored to `main` at merge `81a03000de949e99f258fdbd81402255569d1ea5`; avoid divergent release tags, and ensure APK's release target equals the tested commit.
- Release guard uses **recovered-main ancestry plus critical file checks**, not immutable hashes of invitation/archive source: normal future fixes must remain possible.
- My Space only invokes QA lifecycle APIs in QA builds. Production must still show Profile/My Space without calling missing QA-only RPCs.
- My Archives can be opened even by an **unpaired** user; old-space archives are user-owned rather than current-space-owned.
- JSON `Download my data` is explicitly labeled **unencrypted and media-excluding**, not a media-inclusive secure archive.
- Server-side archive dependency inventory dynamically traces public-schema FK children up to five links, counts records scoped by the signed-in user's space and never returns record contents.
- The inventory finds **35 dependent tables** including comments, revisions, budget logs, scrapbook content and attachment metadata. It identifies **five multi-parent tables** requiring explicit relation ownership review:
  - `occasion_budget_items` — canonical `plan_id` → `occasion_plans`; optional `source_activity_id` is only a reference.
  - `occasion_budget_log` — canonical `plan_id`.
  - `occasion_proposal_items` — canonical `proposal_id` → `occasion_proposals` → `occasion_plans`.
  - `task_checklist_items` — canonical non-null `task_id`; optional legacy task pointer is not canonical.
  - `task_checklist_checks` — canonical non-null `task_id`; also has `item_id`.
- The audit is deliberately **not an authorization to export**, since references across two parents need integrity constraints, and the per-user privacy/media lineage must be proven. `safe_to_export` always returns false.
- **Privacy hardening migration 0155:** signed-in clients receive only schema-level dependency coverage, archive progress and generic blocker summaries—not the partner's private-record counts, root-table cardinalities or nested row detail. The internal scoped audit remains available for server-side verification.
- **Cross-parent integrity migration 0157:** internal-only (never replaces the sanitized public RPC). Checks occasion budgets against optional activity/component references, budget logs vs items, proposal items vs budget plans, checklist checks vs their items, and legacy tasks vs current task relationships. Synthetic cross-space relationship regression passes; all rows rolled back.
- **P0 access hardening migration 0156:** blocked QA account deletion runs as `SECURITY INVOKER`; anonymous users cannot execute it. Security advisor authenticated privileged-function warning count fell from 20 to 19. All real account-deletion operations remain blocked.
- QA SQL regression: inserted a temporary private activity + nested comment, verified count and cross-space isolation; inserted an occasion budget item **without a source activity**, verified it still resolves to its plan; all tests explicitly rolled back. Anonymous RPC execution denied.

## Still unfinished / must not be represented as complete
1. **Canonical classification of all roots and dependent tables.** Inventory counts are not archive serialization; handle mixed shared/private, linked audit rows, cross-parent conflict checks, inheritance and entity/attachment ownership.
2. **Actual media-inclusive encrypted archive generator.** Identity-bound encryption keys, portable recovery, authenticated server Storage, idempotent queue, byte integrity proofs, per-user private + old shared archive. No archive objects exist yet.
3. **Restoration.** Only a user's private archive may be restored into a new space, with dedupe, attachment recovery and inert old shared references. Old shared-history archives remain reference only.
4. **Real lifecycle transition.** After independently verified per-user archives, safely retire old shared data and Storage objects through Storage API, give owner a clean new relationship boundary on leave/removal, unpair B, and leave both unpaired on owner Delete Space. Do not expose old shared history to a new partner.
5. **Delete-account cascade.** Seven-day grace policy and cancellation/notification/retrieval semantics, then archival before account purge. Until then the request RPC must stay blocked.
6. **Lifecycle email, offline/undeliverable partner notifications, iOS explicit external save, cross-device archive recovery, platform link testing** and real phone acceptance.
7. **Security advisor**: remaining privileged public RPCs need permission + abuse-case review; public support API intentionally supports anonymous callers and cannot be blindly revoked without breaking the site.
8. **Release completion**: confirm final QA signed APK, package, certificate, Firebase push, two Android phones, both account roles and not just CI analysis.

## Hard release principles
- Code only merges from a branch based on the current `main`; exact source tag/commit verified.
- Never trigger a signed QA APK for an untested or incomplete final integration.
- SQL changes go QA first, tracked with unique migration numbers, with privilege/RLS tests.
- QA/Production configurations must remain isolated and never delete personal data to pass tests.
- No space/account deletion or partner separation before an independent, all-media archive plus restore proof.
