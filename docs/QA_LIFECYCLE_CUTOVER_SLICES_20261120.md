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

## Continuing QA slices on the same draft branch

| Area | QA database | App implementation | Validation |
| --- | --- | --- | --- |
| Feelings / daily check-ins | Migration `0244`: owner-private journal and current-couple shared check-ins; immutable scope and owner-only private audit; stale-client private writes blocked | Solo journals available with one account; partner conversations remain couple-scoped; personal records do not show legacy share control | Rollback SQL owner/partner/outsider, audit, stale write and immutable scope **PASS** |
| Personal days off | Migration `0245`: owner-private and pair-shared days off, immutable ownership and CRUD; same-day uniqueness retained | Own days-off screen has new personal/shared choice, supports solo entry; unified calendar loads both RLS-authorized scopes | Rollback SQL owner/partner/outsider, edit, delete, immutable scope **PASS** |
| Goals | Migration `0246`: owner-private and current-couple shared Goals, immutable scope, owner-only private action audit | No active Goals UI in current Flutter tree; **backend only** | Rollback SQL owner/partner/outsider, audit, stale writes **PASS** |
| Places and visits | Migration `0247`: account-private / pair-shared root and visit child scope; no private media or cross-couple trip links | Solo Places, unified map, visit entries, personal-only indicator, search/deep link; shared trip planning withheld for personal places | Rollback SQL owner/partner/outsider, parent/child isolation and immutable scopes **PASS** |

| Items to sort / Share-in | Migration `0248`: account-owned private text/link inbox, current-couple shared inbox, owner audit, frozen scope; private file payloads rejected | Unified inbox while solo or paired, private text share-in routing, personal search, no raw visibility toggling; shared-file uploads require verified current couple | Rollback SQL owner/partner/outsider/audit, immutable scope, rejected private attachments **PASS** |

**Integration gates still open:** the Flutter analyzer and two-phone tests have **not** run. The new per-module database tests are rollback-only, not evidence that delete/leave/account-deletion is safe. Private file handling, all previously stored personal rows, cross-module references and old-client compatibility still require work. Draft PR #127 must not be merged, deployed or used to trigger an interim release. No Production data or schema was changed in these slices.

## Checks actually executed

- `supabase/tests/qa_personal_activities_memories_owner_scope.sql` ran successfully on QA with transaction rollback.
- `supabase/tests/qa_personal_saved_contacts_owner_scope.sql` ran successfully on QA with transaction rollback.
- QA Activity, Memory, Activity component and Memory photo row counts remained zero following the first test.
- No Flutter analyzer, Flutter tests, Android build, iOS build, or two-phone acceptance has run from this branch. GitHub billing remains outside the scope of this slice.
- QA migration `0243_qa_personal_saved_contacts_rls.sql` was applied; no Production schema migration applied.
- No irreversible lifecycle action enabled. No old archive/deletion requests treated as consent.

- `supabase/tests/qa_account_owned_daily_checkins_scope.sql`, `qa_personal_days_off_current_pair_isolation.sql`, `qa_personal_goals_current_pair_isolation.sql`, , `qa_personal_places_visits_owner_scope.sql`, and `qa_personal_sort_inbox_text_scope.sql` each passed with rollback on QA.
- Verified the converted QA root/visit tables remained empty after tests, and all five newly protected tables have RLS enabled.

## Work still needed before any QA release / irreversible action

1. Complete two-scope data + RLS cutovers for every remaining root and child: Trips, Occasions, Places, Goals/check-ins, experiences, gestures, letters, sort items, links, days off, cross-module histories and attachments.
2. Complete account-owned Storage for private photos/voice/files and safe shared access revocation; migration of existing legacy private content with creator mapping, child integrity and checksums.
3. Finish immutable or explicitly authorized visibility transfer semantics, search/realtime/push/mentions and all direct launch routes; static analysis and full automated test suite.
4. Transactional delete of old couple's shared data while preserving both personal namespaces; two phone A/B/C and race tests before enabling Leave, Remove or Delete Space.
5. Cancellable 7-day account deletion request + authenticated scheduled finalization, shared erasure, user-auth removal, survivor unpaired and survivor-private preservation.
6. Remove unreachable My Archives and obsolete invitation setup cards; validate signup and branding; one QA build after all gates, Production only upon founder approval.

**Release policy:** No intermediate APK, no GitHub Actions release/upload run, no Production rollout. The founder will fix GitHub billing only at the end.
