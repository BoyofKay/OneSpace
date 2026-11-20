# OneSpace definitive relationship lifecycle — NO ARCHIVING (2026-11-20)

This specification **replaces** the November 2026 verified archive/restore workflow. **No archive, export, download link, email, restore or archive progress step belongs to any relationship or account deletion action.**

## Rules and durable state

The original space `S1` has original owner `A` and invited member `B`. Personal content means `visibility='private'` and is owned only by its original `created_by` or correct owner field. Shared content means `visibility='shared'` or `shared_only`, plus associated shared history, reactions, attachments, media, notifications and mixed-scope edges.

1. **A removes B:** after an explicit irreversible-loss warning and authenticated confirmation, immediately end the relationship, revoke B membership/invitations/tokens to S1, and permanently delete **all** old S1 shared content and shared storage. Keep A's private content in S1 (now an unpaired space); move B's private content, with private dependent records and private media, into B's new solo space so B can view/edit it immediately. Existing private IDs are preserved where safe. Prevent any new couple from inheriting earlier shared history.
2. **B leaves:** identical outcomes for A and B. B never deletes A's private content; the authenticated transaction enforces member identity.
3. **A deletes S1:** confirm same loss, destroy S1 shared content and revoke current pair access. Create/retain independent solo spaces for A and B and **move both users' private root/dependent content before dropping S1**, because all existing private root tables have mandatory S1 foreign keys with ON DELETE CASCADE. Both members remain signed in as unpaired.
4. **C joins A's S1:** only A's authorized private data may already be present; C cannot access it. No old shared data exists. C brings their own personal private records from their prior solo space into S1, or use future independent private namespace if migrated, without duplicating relationships or leaking private content.
5. **B joins S2:** move B's owned private records from B's solo space into S2 (while preserving ownership/visibility) before retiring B's old solo space. B can remain unpaired and read/edit them instead.
6. **Account deletion:** seven calendar days after explicit request, *not at request time*, delete target account, its personal/private data, personally stored files, sessions and devices, all shared relationship data, and leave the surviving member unpaired with their private data intact. Cancellation during the seven days leaves all account and relationship records untouched. If the deleted user was S1 owner, transfer space ownership to survivor or allocate a clean solo space before deleting the original owner auth identity. Ensure the worker is idempotent and retries incomplete storage deletion safely; never report full success on partial cleanup.

**No new relationship may inherit old shared content.** A solo user needs their own space/namespace even if they were previously invited.

## Irreversible warning copy

Title (remove / leave / delete space): **Permanently delete our shared content?**

Body: **This action ends the current shared space relationship and permanently deletes all content shared between you and this partner, including shared activities, notes, tasks, conversations, memories, and attachments. OneSpace cannot restore the deleted shared content. You and your partner will each keep only the private content you personally created. The other person's private content will never be shared.**

Action buttons: **Cancel** / **Delete shared content and [remove partner | leave space | delete space]**. Require a deliberate destructive acknowledgment/confirmation, not a harmless `Prepare securely` button. Display exact partner/action context and avoid cross-action language.

Title (account): **Schedule permanent account deletion?**

Body: **Your account and all your personal information will be permanently deleted after 7 days. The shared content with your current partner will also be permanently removed. Your partner keeps their own private content and becomes unpaired. You can cancel before the seven-day deadline; no data is deleted during the grace period. OneSpace cannot restore data after deletion completes.**

Buttons: **Cancel** / **Delete my account in 7 days** (with explicit deliberate confirmation). The authenticated owner alone can request/cancel their own account deletion.

## Security/engineering requirements

- **Keep database actions atomic:** server transaction holds a lock on original space, verifies the actor's current role and exact members, checks no concurrent join/leave/delete, rehomes private roots and every private child, sanitizes mixed references and shared pointer fields, permanently deletes shared root/dependent rows, updates membership and ownership, and commits only when private preservation is proved. On any mismatch raise an error and roll back **everything**; never leave an orphaned private record.
- **Private attachments preserved; shared attachments erased:** storage objects are not transactional with PostgreSQL. Immediately revoke Storage read access on shared objects with DB tombstones/row removal, then delete the actual bytes through idempotent post-commit cleanup jobs, auditing all failures. Private media must be moved/rekeyed without breaking private access. Deleting a database row is not sufficient if its Storage object remains public or signed links remain live.
- **Audit cross-module edges:** all 69 historically classified source families, including dependents, history, contacts, notes, checklist items, reminders, gestures, calendar, space events, comments, reviews, notifications, trips, uploaded private/shared media, and any pointers inside JSON. These are deletion/preservation categories now, not archive types.
- **User/space attribution:** all private roots currently carry nonnullable `space_id`, normally a cascade FK into `spaces`. An unpaired user must therefore still have a valid solo `spaces` row. No user may have two active `space_members` rows. Any join moves owned private records before old solo space deletion. Ownership checks always use database-authenticated `auth.uid()` and verified roles.
- **RLS and triggers:** ensure all existing policies and SECURITY DEFINER RPCs deny former members or future partners access to prior private records. Update private-vault mirror triggers and any task/trip cross-reference guards for legitimate private rehoming. Never skip triggers broadly or turn off RLS to make migration pass.
- **Account purge worker:** QA R59 worker currently deliberately retains shared content and soft-deletes auth identity. Replace that workflow. Test cancelled, due and already-deleted branches; prevent deletion during grace. Real deletion and its storage purge should be auditably completed, not inferred from task submission.
- **Legacy QA preparation requests:** two actual `awaiting_verified_export` jobs exist. They were signed under an old **non-destructive** "Prepare securely" warning. Never automatically convert these into permanent deletion commands. Ask their respective authenticated initiators to reconfirm using the new irreversible warning after the new transaction is tested.
- **Production:** no Production migration, change or account mutation before QA acceptance. Keep old audit logs only with limited privileged access if required; remove My Archives UI, archive generation routes and cron once no longer used. QA inventory schedule was unscheduled by 0226. Keep janitor on QA only to destroy any pre-existing temporary staging objects safely.
- **Backups:** "cannot restore in OneSpace" is a truthful product promise; normal database disaster-recovery backups may still temporarily retain encrypted copies under the platform's retention policy. Do not falsely claim all backup media is instantly physically erased.

## Acceptance matrix

- Both members private text + private file persist across all three relationship exits, including unpaired state and joining a *new* space.
- All shared root/dependent records, cross-references and media become inaccessible immediately. Storage physical cleanup finishes with auditable retries.
- A new partner C sees no B private records and no previous shared A/B history, even via old IDs, REST, RPC, push, Storage URLs or cached app state.
- Explicit negative security tests: unauthorized stranger cannot remove another member; invited B cannot delete A's space; repeated concurrent exits are idempotent; revoked users cannot read old space by stale JWT.
- Seven-day request/cancel/purge on both owner and invited partner; surviving member remains unpaired, retains own private items and media. All exact-date calculations are server-side.
- Heavy dataset, chain of private dependent records, mixed-visibility content, media references, failed storage cleanup, cross-space join, QA-vs-Production isolation; zero private data loss.

## Implementation status at specification date

The policy and QA archive schedule retirement are recorded. **Actual relationship removals and account deletion remain disabled** while rehoming, permanent shared purge, private RLS regression and seven-day purge behavior are implemented/tested. Both original preparation requests remain recorded but have NOT executed. No Production changes.
