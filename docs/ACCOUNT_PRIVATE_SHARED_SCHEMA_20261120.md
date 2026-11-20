# OneSpace — unified UI, two independent data scopes (approved 2026-11-20)

## Product contract

Each person always owns **one private space**, by Auth account ID. Each *current, specific couple* owns **one separate shared space**, by relationship space ID and its exactly authorized members. An unpaired person still has their private space. OneSpace shows ONE experience for Today, Remember, Coordinate, Connect and other modules. Every object editor uses the same screen and a visibility selector:

- Private -> user-owned private-space ID. Independent of partner join/leave/remove/delete space.
- Shared -> current relationship's shared-space ID. Accessible by current pair only, and permanently erased when that relationship ends.
- No pairing -> private creation works; shared creation is not available.
- A new relationship starts with a brand-new shared scope. No previous shared content is inherited.
- Changing visibility must be an authorized atomic move: private -> shared explicitly exposes content to partner; shared -> private cannot silently duplicate formerly shared data or grant the prior partner access.
- Replies, checklists, comments, mentions, audit revisions, files and Storage objects must inherit the correct parent scope and remain private or shared. No orphaned children or cross-scope links.

## Physical model and why not duplicate every content table

`public.user_private_spaces` is the **personal namespace** (one immutable owner UUID, unique per active Auth account), while existing `public.spaces` + `public.space_members` are the current relationship namespace (with legacy singleton spaces temporarily supported). Eligible root tables keep one schema with mutually exclusive references: existing `space_id` for relationship-scoped content, new `private_space_id` for account-scoped content. There are 22 eligible root families, not 44 separately duplicated content tables.

Supabase RLS and every read/write/RPC must check the owner for private references; shared scope uses actual currently paired membership. The UI service eventually combines both queries into one list and routes one create/edit screen based on requested visibility. Personal and shared content need correct separate Storage and notification authorization.

## Completed QA foundation

Migration 0227: `user_private_spaces`, one automatically on Auth signup and one for each existing active QA user. Creator-only read RLS, no arbitrary client INSERT/UPDATE/DELETE. Read-only `public.my_storage_scopes()` returns private ID, shared ID only when paired, and legacy space, with `content_routing_enabled=false` until the full cutover.

Migration 0228: all 22 eligible root tables have nullable `private_space_id` referencing `user_private_spaces(owner_id)`, nullable legacy `space_id`, and mutually exclusive space-scope constraints. Where available, source creator and `visibility='private'` checks apply to the new personal path. Existing rows are untouched, and legacy creates remain on their former path; no private data is yet moved.

Flutter: retire old 'prepare secure archive' actions and remove My Archives from Me. My Space transparently shows the permanent shared-loss rule, disabled destructive actions until safe, and prior unexecuted preparation requests with their cancel option. Account deletion screen now explains the correct seven-day private/shared policy but keeps the destructive request disabled.

Account-purge QA Edge Function v7: **legacy soft-delete and keep-shared path removed**. Active runner fails CLOSED if any due entries appear until true survivor-preserving v2 finalizer is deployed. Existing `request_account_deletion`, `purge_due_accounts_list`, and `purge_account_data_service` remain disabled; no account has been purged or scheduled.

## Remaining mandatory cutover before any destructive action is enabled

1. **Data migration**: audit 69 family policies, 22 roots, dependent edge references, all authored private records (including private media); re-home private rows to `private_space_id`, clear legacy `space_id`, retain correct author/visibility, and prove per-user record counts and checksums unchanged. Non-author-owned tables need explicit ownership mapping.
2. **RLS, triggers and APIs**: write authenticated owner-only private policies and paired-only shared policies in every affected table, RPC, Storage rule, notification, active stream and query. Existing legacy private RLS requires membership, so it must be migrated before data movement. No broad grants or bypassing RLS.
3. **Unified app reads/writes**: use `my_storage_scopes()` and a common scope resolver for every create/edit/list/view; private works when solo; refuse shared write without a current pair; update realtime, search, mentions, navigation, deep links and caches. Flip server + app feature flags only after all compatible clients accepted.
4. **Irreversible relationship transaction**: authenticated explicit warning, lock pair, record exact member IDs, delete all shared roots and children/storage pointers, revoke invitations and former access, detach B or retire pair, and leave both personal namespaces unchanged. If anything would delete personal data or orphan dependent rows, roll back. Storage byte deletion postcommit needs idempotent retries; access revocation must be immediate.
5. **Account deletion**: implement true seven-day request/cancel with exact UTC expiry, no early changes, scheduled finalizer (user + their personal content + current pair shared content erased, surviving partner private untouched/unpaired), Storage cleanup and auth/account record deletion with accurate status + retry. The old runner now fails closed and may NOT silently retain shared content.
6. **QA tests**: user A/B remove, leave, close, join C, B join new partner, unpaired content CRUD, bidirectional visibility changes, heavy 69-family dataset, private file preservation and shared storage deletion, stale JWT attacks, and cancel vs deadline races. Test both phones. Production isolated.

No archival, export/download link, data restore or retention workflow is a prerequisite to relationship/account actions. Optional standalone manual 'Download my data' is a separate user-initiated export, not part of this lifecycle.
