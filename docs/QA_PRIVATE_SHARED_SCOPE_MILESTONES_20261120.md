# QA two-scope lifecycle cutover — progress and next gates (20 November 2026)

**Authoritative product policy:** [ADR-2026-11-20](ADR_2026-11-20_PERSONAL_SHARED_OWNERSHIP_AND_DELETION.md). This is a status report, not a new decision.

## Completed and merged

| PR | Outcome | Verification |
|---|---|---|
| [#119](https://github.com/BoyofKay/OneSpace/pull/119) | Final no-archive, account-owned private space / current-pair shared space, irreversible warnings and seven-day account-deletion rules captured in ADR + Decision Log | Merged |
| [#118](https://github.com/BoyofKay/OneSpace/pull/118) | QA private and shared **Notes** through one interface. Account-owned private RLS + personal audit; paired shared notes; search, voice and share-in routes | Flutter analyze/tests green; authenticated DB rollback tests owner/partner/outsider green |
| [#120](https://github.com/BoyofKay/OneSpace/pull/120) | QA private and shared **To-do and Checklists** through one interface, including solo private lists. Private task, checklist items/checks and audit scoped to account; paired shared lists. No legacy archive mirror required for new personal tasks | Flutter analyze/tests green; authenticated DB rollback tests owner, partner, outsider, child/check and audit green |
| [#117](https://github.com/BoyofKay/OneSpace/pull/117) | Personal namespace per account, all 22 eligible content root tables prepared with mutually exclusive scope columns; obsolete account-deletion path retired | QA migrations & RLS contract tests green |
| [#116](https://github.com/BoyofKay/OneSpace/pull/116) | Archive inventory schedule retired, no-archive policy adopted | QA cron absent |

### Latest QA integrity and state

- Notes, Tasks, checklist-item and checklist-check test records: **0**, verified after all rollback-only tests.
- Space memberships: **6**; pending account deletions: **0**.
- The two original preparation requests are **cancelled** (`partner_leaves` transition 2026-11-20 03:03:48 UTC; `owner_removes_partner` transition 2026-11-20 03:04:44 UTC). **Neither was executed as an irreversible membership/deletion action.** This check does not establish who cancelled them.
- Obsolete archive inventory cron: **0 scheduled**. 
- QA security advisor still has pre-existing warning categories: 7 `rls_enabled_no_policy`, one anonymous-executable security-definer category, and 18 authenticated-executable security-definer category findings. The last scan did not mark Notes/Tasks changes, but those warnings are **not** closed by these PRs.
- **Production untouched. No signed QA APK has been generated from the new Notes/To-do code.** It is merged in source and backed by applied QA migrations, not yet two-phone acceptance-tested.

## Mandatory next engineering gates, in priority order

1. **Finish module scopes**, not new duplicate UIs: Calendar, Activities, Reminders, Memories, Contacts, Trips, and all other applicable roots and descendants. Normalize direct-create routes, unified search/realtime, mention handling, shared-to-private/vice-versa editing, and unpaired access.
2. **Private file and child ownership:** Notes photos/linked references remain deliberately unavailable for newly account-owned private records until independent Storage, child policies, and access revocation are verified; same for other module attachments. Ensure private files remain accessible after leave/space deletion.
3. **Legacy records and old-app compatibility:** migrate any existing legacy `visibility='private'` roots and dependents into account-owned scopes without data loss. Verify snapshots/checksums and retain rollback plan. Do not change their `space_id` blindly; stale app versions must not reintroduce private rows to couple storage.
4. **Immediate relationship lifecycle:** transactional remove/leave/delete shared scope after deliberate irreversible warning, with all former-couple shared roots, children, media pointers and session access revoked. Private account scopes unchanged. Retryable physical file cleanup after DB commit. Test races, new partner C, and leave/unpaired state on two phones.
5. **Seven-day account deletion:** request shows exact expiry, no deletion during grace; cancellation restores normal account status. At deadline, idempotent deletion of requester + requester private + current couple shared; survivor private untouched and survivor unpaired. Verify auth sessions, Storage, notification and login safety. Legacy keep-shared soft purge is forbidden.
6. **Launch gates:** QA data integrity, permissions/RLS, heavy and empty datasets, false/failed network, Android and iOS QA builds, Production isolation, then deliberate staged Production release.

**Safety rule:** Until steps 1–5 pass, destructive relationship and account deletion controls remain disabled. No archive, restore, My Archives or 30-day delivery scheme is part of this lifecycle.
