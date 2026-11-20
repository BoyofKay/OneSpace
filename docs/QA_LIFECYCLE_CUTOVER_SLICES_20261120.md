# OneSpace QA two-scope lifecycle — active implementation slices (20 November 2026)

**Source of truth:** [ADR](ADR_2026-11-20_PERSONAL_SHARED_OWNERSHIP_AND_DELETION.md). This is an engineering progress record, **not** a declaration that destructive actions are safe.

## Source changes on `qa/activities-memories-two-scope-cutover-20261120`

| Area | Implemented in QA branch | Backend validation | Remaining gate |
| --- | --- | --- | --- |
| Activities | Unified private/current-couple list, personal creation while solo, shared creation while paired, private-only screen restrictions for unapproved media/link actions; no Production-routing change | Rollback SQL: owner/partner/outsider, child step, shared read, ownership immutability **PASS** | Realtime/notifications, comments/revisions/decision RPCs, Storage, full app tests, stale clients, cross-source links |
| Memories | Unified private/current-couple stories; solo story creation; shared media retained; account-owned private photo upload and scrapbook creation withheld | Rollback SQL: owner/partner/outsider, shared read, ownership immutability **PASS** | Private media and scrapbook Storage model, file revocation, cross-linked records, app tests |
| Direct saved contacts | New QA migration 0243 for private-owner/current-pair policies and immutable scope; unified private/shared cards and phone import | Rollback SQL: owner/partner/outsider, direct contact edit, history and visibility mutation rejection **PASS** | Cross-module linked contacts, memory/Activity references, legacy rows and lifecycle erasure |
| Global Search | QA private+shared title/body searches for Activities/Memories and direct Contacts, including solo mode; Calendar QA lookup now uses RLS scope | Source updated, **not** app tested | Two-phone search and deep-link verification |
| Production | Guarded behind `OneSpaceEnv.isProduction` for app read/write paths; QA-only SQL migration applied to QA | Production **not modified by this slice** | Do not deploy to Production until approved |

## Checks actually executed

- `supabase/tests/qa_personal_activities_memories_owner_scope.sql` ran successfully on QA with transaction rollback.
- `supabase/tests/qa_personal_saved_contacts_owner_scope.sql` ran successfully on QA with transaction rollback.
- QA Activity, Memory, Activity component and Memory photo row counts remained zero following the first test.
- No Flutter analyzer, Flutter tests, Android build, iOS build, or two-phone acceptance has run from this branch. GitHub billing remains outside the scope of this slice.
- QA migration `0243_qa_personal_saved_contacts_rls.sql` was applied; no Production schema migration applied.
- No irreversible lifecycle action enabled. No old archive/deletion requests treated as consent.

## Work still needed before any QA release / irreversible action

1. Complete two-scope data + RLS cutovers for every remaining root and child: Trips, Occasions, Places, Goals/check-ins, experiences, gestures, letters, sort items, links, days off, cross-module histories and attachments.
2. Complete account-owned Storage for private photos/voice/files and safe shared access revocation; migration of existing legacy private content with creator mapping, child integrity and checksums.
3. Finish immutable or explicitly authorized visibility transfer semantics, search/realtime/push/mentions and all direct launch routes; static analysis and full automated test suite.
4. Transactional delete of old couple's shared data while preserving both personal namespaces; two phone A/B/C and race tests before enabling Leave, Remove or Delete Space.
5. Cancellable 7-day account deletion request + authenticated scheduled finalization, shared erasure, user-auth removal, survivor unpaired and survivor-private preservation.
6. Remove unreachable My Archives and obsolete invitation setup cards; validate signup and branding; one QA build after all gates, Production only upon founder approval.

**Release policy:** No intermediate APK, no GitHub Actions release/upload run, no Production rollout. The founder will fix GitHub billing only at the end.
