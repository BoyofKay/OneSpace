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

| Trips, itinerary, flights, messages, revisions | Migration `0249`: account-owned personal root and current-pair shared root; child tables inherit parent RLS; immutable owner/parent/scope; account-private document uploads blocked | Unified personal/shared Trips including solo editor, message notes, trips and itinerary in search; personal Storage, linked items, shared counters and automated preparation features withheld | Rollback SQL verifies owner/partner/outsider, private/shared children, audit, mutation and stale-client guards **PASS** |
| Occasions, budgets, steps, proposals | Migrations `0250`–`0252`: account/private and current-pair roots and child RLS, cross-scope Activity link rejection, same-plan proposal associations and legacy budget validator updated | Personal occasion editor with solo mode, account-private preparation reminder, safe filtered Activity-option linking, personal search; shared-only links/counters withheld | Rollback root/child/audit **PASS** and privileged proposal association mismatch rejection **PASS** |

| Love letters | Migration `0253`: account-owned private unsent drafts, current-pair sent letters and read receipts, immutable owner/space and no raw send of a private draft | Personal draft list/compose while solo; sending a copy to current partner preserves the account draft | Rollback SQL owner/partner/outsider, send/draft, receipt, mutation guard **PASS** |
| Gesture messages (partial) | Migration `0254`: account-owned preset overrides, current-pair sent gesture history and recipient checks; partner-addressed templates/schedules remain couple-scoped | QA preset customization now persists under signed-in account even when paired; existing send controls remain pair-only | Rollback SQL owner/partner/outsider, immutable preference ownership, sent delivery **PASS** |
| Experiences and history | Migrations `0255`–`0256`: new private scope and visibility, current-pair sharing, child comments/interests/reviews/revisions, account-only action and comment audits | Unified private/shared list and solo creation, visibility indicator, personal search/Share-in, partner-link/mention controls withheld on private records | Rollback SQL owner/partner/outsider, root/child/revisions, action and comment history **PASS** |

**Integration gates still open:** the Flutter analyzer and two-phone tests have **not** run. The new per-module database tests are rollback-only, not evidence that delete/leave/account-deletion is safe. Private file handling, all previously stored personal rows, cross-module references and old-client compatibility still require work. Draft PR #127 must not be merged, deployed or used to trigger an interim release. No Production data or schema was changed in these slices.

## Checks actually executed

- `supabase/tests/qa_personal_activities_memories_owner_scope.sql` ran successfully on QA with transaction rollback.
- `supabase/tests/qa_personal_saved_contacts_owner_scope.sql` ran successfully on QA with transaction rollback.
- QA Activity, Memory, Activity component and Memory photo row counts remained zero following the first test.
- No Flutter analyzer, Flutter tests, Android build, iOS build, or two-phone acceptance has run from this branch. GitHub billing remains outside the scope of this slice.
- QA migration `0243_qa_personal_saved_contacts_rls.sql` was applied; no Production schema migration applied.
- No irreversible lifecycle action enabled. No old archive/deletion requests treated as consent.

- `supabase/tests/qa_account_owned_daily_checkins_scope.sql`, `qa_personal_days_off_current_pair_isolation.sql`, `qa_personal_goals_current_pair_isolation.sql`, `qa_personal_places_visits_owner_scope.sql`, `qa_personal_sort_inbox_text_scope.sql`, `qa_personal_trips_and_children_scope.sql`, `qa_personal_occasions_children_scope.sql`, and `qa_occasion_proposal_plan_link_guard.sql` each passed with rollback on QA.
- `qa_account_owned_letter_drafts_and_sent_pair_scope.sql`, `qa_personal_gesture_overrides_pair_delivery.sql`, and `qa_personal_experiences_children_scope.sql` passed with transaction rollbacks, including account-only Experience comment action history.
- Verified previously converted QA roots/visit tables remained empty after earlier tests; the newer domain counts must be rechecked before release. RLS is enabled on converted tables.

## Work still needed before any QA release / irreversible action

1. Finish **remaining** scope/data cutovers: partner-addressed gesture templates and automated schedules, general Links and linked records, private media/attachments and cross-module dependencies. Trips, Occasions, Letters and Experiences now have QA database/app slices but require full app tests and legacy migration.
2. Complete account-owned Storage for private photos/voice/files and safe shared access revocation; migration of existing legacy private content with creator mapping, child integrity and checksums.
3. Finish immutable or explicitly authorized visibility transfer semantics, search/realtime/push/mentions and all direct launch routes; static analysis and full automated test suite.
4. Transactional delete of old couple's shared data while preserving both personal namespaces; two phone A/B/C and race tests before enabling Leave, Remove or Delete Space.
5. Cancellable 7-day account deletion request + authenticated scheduled finalization, shared erasure, user-auth removal, survivor unpaired and survivor-private preservation.
6. Remove unreachable My Archives and obsolete invitation setup cards; validate signup and branding; one QA build after all gates, Production only upon founder approval.

**Release policy:** No intermediate APK, no GitHub Actions release/upload run, no Production rollout. The founder will fix GitHub billing only at the end.
