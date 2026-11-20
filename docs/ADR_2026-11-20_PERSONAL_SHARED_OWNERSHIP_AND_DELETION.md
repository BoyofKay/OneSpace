# ADR-2026-11-20 — Independent private content, relationship-owned shared content, and irreversible lifecycle

**Status:** ACCEPTED — authoritative product decision; implementation in progress (QA first).  
**Decided:** 20 November 2026.  
**Supersedes:** The 19–20 November partner separation **archive/export/restore**, archive-before-separation, `awaiting_verified_export` readiness and asynchronous My Archives proposals; see supersession notices in older documents.  
**Companions:** `DECISION_LOG.md`, `ACCOUNT_PRIVATE_SHARED_SCHEMA_20261120.md`, `NO_ARCHIVING_RELATIONSHIP_LIFECYCLE_20261120.md`.  
**Scope:** Android, iOS, backend, Auth, Storage, audit/history, invitations, search, notifications; QA prior to Production.

## How we arrived here — discussion and final choices

1. **Problem found:** On QA, a person asked to *remove a partner* and another asked to *leave*. Both remained at `awaiting_verified_export`; neither request had progressed. The old separation process demanded verified private/shared archives before membership could change. Even empty user content stalled, because the archiving/export/restore engine was incomplete. That was unacceptable user experience.
2. **Intermediate idea (rejected):** Make separation immediate, then asynchronously enumerate, encrypt, verify, deliver and delete archive files, showing My Archives progress and 30-day temporary links; delay account deletion by seven days, with cancellation of archive jobs. Some prototype inventory infrastructure and UI were built while discussing this, but this is **NOT** the approved product behavior.
3. **Final decision:** **NO automatic archiving, export, restore, email links, 30-day archive windows, or My Archives** as part of leaving, removal, space deletion, or account deletion. Instead, show explicit irreversible warnings and carry out the destructive relationship transition immediately after confirmed consent. Each person keeps every private record they own; all former-couple shared data is permanently removed. OneSpace will not restore erased shared data. Ordinary provider disaster-recovery backups are subject to their own retention policies and are not a user archive.
4. **Root-cause fix:** Previously many private items had `space_id` and cascading foreign keys, so deleting a couple space risked deleting a user's personal records. The founder chose **two separately owned backend scopes per account**: (a) their permanent account-owned personal/private space; and (b) a relationship-owned shared space for the **specific current pair**. Content marked Private belongs in (a); Shared belongs in (b). The app must still provide **one Notes/Tasks/Activities/etc. creation, editing, list and search experience** — not duplicate modules. The implementation may reuse a content table with mutually exclusive `private_space_id` and `space_id`; it does not need physically duplicated tables.
5. **Delete-account rule replaced:** The earlier soft-delete/retain-the-couple's-shared-content worker is rejected. **Seven full days of grace**, cancellable any time before the deadline, with *no deletion of account, private or shared content during the grace period*. At deadline: permanently delete the requesting account and their private data, and delete the current pair's shared data; keep the other account's private content and unpair that user.
6. **Execution agreement:** Implement without asking the founder to re-decide settled rules. Document decisions in repo; complete and test via QA; do not touch Production or activate irreversible actions before end-to-end private-preservation and shared-erasure tests pass.

## Invariants — never violate

- Each authenticated account has **exactly one persistent owner-only private namespace**. An unpaired person can read and create private content. Private records, children, audit history and files stay with the account across leave/remove/close/re-pair. Never expose them to a prior or future partner by default.
- Each specific relationship has a **distinct shared namespace** and two authorized members at most. Any newly formed relationship gets a clean shared scope — never recycle old shared records or grants.
- An object has **one storage ownership scope**; `Private` and `Shared` selections route writes accordingly. UI merges authorized content in one interface and retains the chosen visibility while editing.
- Only the current owner may write private records, and the specific current pair may read authorized shared records; enforce in PostgreSQL RLS, security-sensitive RPCs, Storage, push, search, realtime, child links and audit. A previously paired user, a new partner and a guessed object ID must not bypass this.
- Edges/children inherit their parent's scope; cross-scope links never reveal private content to the shared partner. File access must be revoked immediately when shared content is deleted; idempotent background *physical file cleanup* is allowed, but not a user archive.
- Do not silently change a saved item's visibility; moving Private→Shared is deliberate disclosure and needs explicit authorization. Shared→Private cannot be used to steal the couple's shared data before separation; implement authorized ownership and lifecycle rules.
- Database state changes and all required integrity checks occur in a transaction, or roll back completely. Storage byte removal is not transactional; use access revocation and an auditable, retryable deletion queue.
- Disabled lifecycle controls stay disabled until *all* relevant private/media preservation, shared data/children deletion, RLS, storage and concurrency tests pass. **No automatic conversion of old archive-preparation requests** into deletion consent.

## Final user journeys

| Scenario | Timing | Private records | Old shared records | Post-state |
|---|---|---|---|---|
| **A removes B from Space 1** | Immediately after deliberate warning/confirmation and safe DB transaction | A and B each keep own content | Permanently delete all former A/B shared content, history and shared files | A unpaired in own space; B unpaired in own private space |
| **B leaves Space 1** | Same | A and B each keep own content | Same permanent deletion | Both unpaired and private content readable |
| **A deletes Space 1** | Same | A and B each keep own content | Same permanent deletion | Shared Space 1 gone; both retain account-owned private space |
| **C joins A later** | Standard join/accept flow | A's and C's personal scopes isolated | No previous A/B shared history available | New distinct shared scope for A+C |
| **B joins Space 2, or stays unpaired** | Standard join/accept flow | B's same personal scope, unchanged | Never import old A/B shared content | New relationship has only newly shared items |
| **A or B requests account deletion** | No deletion during 7 full days; may cancel | All current accounts' data untouched during grace | Untouched during grace | Pending, with deadline/status and cancellation |
| **Account deletion cancelled before deadline** | Immediate cancellation | All users' private records unchanged | All shared records unchanged | Relationship and account stay as they were |
| **Account deletion finalizes after 7 days** | At expiry via authenticated, idempotent worker | Requester account + requester private records permanently deleted; survivor's private data retained | Delete that pair's shared content | Survivor unpaired, retains private namespace; revoked deleted user sessions |

**Delete Space** is not **Delete Account**. Losing relationship data is immediate on space action; deleting an account always has the seven-day grace period.

## Required warnings, confirmations and progress

**Leave / remove / delete shared space**: Explain prominently *“The shared content with this partner—including shared activities, notes, tasks, conversations, memories, history, and shared files—will be permanently deleted and cannot be restored in OneSpace. Both of you will retain only your own private content.”* Show exact target space/partner and action-specific destructive button. A deliberate confirmation is required; Cancel is the default. Do not claim the user is “preparing securely” or “waiting for archives.”

**Delete account**: Explain *“In seven days, your account and its private data will be permanently deleted. Your current relationship's shared content will also be permanently deleted. Your partner keeps their own private data and becomes unpaired. Cancel any time before the deadline to keep everything.”* Display a reliable server-side UTC deadline and cancellable pending state. No deletion may happen during grace. Confirmation requires a deliberate action.

**UI:** One unified Today, Remember, Coordinate, Connect and Me; one create/edit/list per object kind; explicit visibility selector; owner-only content remains available while unpaired. There is **no My Archives progress tab**, no archive emails or delivery/restore workflows.

## Technical model and phased work

- Personal namespace: `public.user_private_spaces(owner_id → auth.users.id)` (one per person), independent of couple.
- Relationship namespace: distinct `public.spaces` + `space_members` for pair (legacy singleton rows must be handled explicitly during migration).
- 22 eligible root families already received nullable `private_space_id`, mutually exclusive with `space_id`; 69 classified source families (roots and dependents) must be audited before destructive actions.
- A unified per-item owner-/pair-authorized read/write layer, used by app and every privileged API; do not assume a legacy `space_id` query can see a personal record.
- Migrate legacy Private records and descendants only when ownership, checksums, file references and RLS are verified; no blind `space_id = NULL` updates on already populated modules.
- Start with Notes then extend to Tasks, Calendar, Activities, Reminders, Memories, Contacts, Trips, linked records, attachments, cross-module search, change history and notifications.
- Rework seven-day account request/cancel/finalizer; old keep-shared worker must stay retired.
- Implement atomic leave/remove/close shared-erasure, revoke storage/notification access, use idempotent storage cleanup, and verify on both phones with heavy datasets.

## Status (as checked 20 Nov 2026)

- QA: personal namespace and 22-root exclusive scope schema; source inventory archive cron retired; legacy archive request and deletion RPCs fail closed. PR #117 merged.
- QA: Notes private/shared RLS and scoped audit database tests pass; PR #118 app cutover in validation at decision-writing time (do not assume merged until verified).
- **Not yet operational:** all-module migration, private media/child ownership, permanent shared-data deletion, seven-day account finalizer and release acceptance. Irreversible controls remain disabled. Two old `awaiting_verified_export` QA requests are **not deletion authorizations**; original requesters must reconfirm under the new warning.
- Production unchanged.

## Explicitly superseded documentation

The following files are historical exploration or outdated design and **MUST NOT** be used as current implementation instructions:
- `ONESPACE_PAIRING_SEPARATION_ARCHIVE_RESTORE_DECISIONS_2026-11-19.md`
- `QA_ARCHIVE_COVERAGE_CATALOG_20261120.md`
- `ASYNC_ARCHIVE_LIFECYCLE_20261120.md`
- `QA_LIFECYCLE_IMPLEMENTATION_SLICE_1_2026-11-19.md`, `QA_LIFECYCLE_IMPLEMENTATION_SLICE_2_2026-11-19.md`
- `QA_REMAINING_LIFECYCLE_GATES_2026-11-19.md`
- `PROPOSED_SIMPLIFIED_SEPARATION_NO_ARCHIVE_20261119.md` (intermediate ideas)
- Any “must archive before separation,” “download 30-day link” or “restore old shared couple history” language anywhere in the repo.

**This ADR controls when older records conflict. Change only by a newly recorded founder decision.**
