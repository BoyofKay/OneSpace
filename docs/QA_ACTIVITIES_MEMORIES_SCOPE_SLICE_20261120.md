# QA slice — Activities and Memories account-owned scope (20 Nov 2026)

**Status: source changes prepared for review; NOT a completed, released or two-phone-tested module.**

Policy source: [ADR-2026-11-20](ADR_2026-11-20_PERSONAL_SHARED_OWNERSHIP_AND_DELETION.md).
Tagline remains **Two of Us. One Space**. This slice does not change the tagline.

## What this branch changes
- `AccountContentScope` calls QA `my_storage_scopes()` and verifies that the personal namespace belongs to the authenticated account. Production retains its pre-cutover routing.
- Activities: new personal records use `private_space_id` with no `space_id`; paired shared records use current `space_id`. Solo personal creation is supported in Coordinate. The list combines both scopes through existing RLS. Quick Add research uses the same scope resolver.
- Activity image and voice services choose personal versus shared Storage buckets from the authenticated RLS-visible parent. QA media payload/voice-message metadata carry the correct bucket identifier. Playback and preview sign within the same parent scope.
- Memories: journals, daily selfies and list/deep-link retrieval include solo account-owned records, while paired shared records remain supported. Personal photos upload into `onespace-private-memory-photos`; signing checks RLS-visible photo metadata. Signed URL cache is partitioned by user.
- The UI hides the shared-creation selector when unpaired for these new editors. There is no automatic archive, export, restore, or separation-triggered move.

## Database verification on QA (transaction ROLLBACK; no lasting rows)
1. Simulated authenticated account A: create/read a personal Activity, a step child, and a personal Memory. **Passed**.
2. As authenticated account B: cannot read A's Activity or Memory; switching to A restores access. **Passed**.
3. Post-test QA counts: Activities 0; Memories 0; Activity components 0; Memory photos 0. **Verified**.

SQL regression: `supabase/tests/qa_personal_activities_memories_owner_isolation.sql`.
Pure Dart routing tests: `test/account_content_scope_test.dart` (five cases, **not executed**).

## Not complete / required before merge or release
- Flutter compile/analyze and test suite: **not run**. No local Dart/Flutter SDK in this execution environment, and GitHub Actions build/upload remains subject to account billing/runner availability. PR is deliberately **draft**.
- Full Activity descendants: comment/component paths need deeper integration and negative tests. Unsupported private component types, mentions, notifications, links, search and audit remain open.
- Memory descendants: personal scrapbooks/pages/invites, private photo roundtrip, signed-URL revocation and two-account Storage tests remain open.
- Legacy private rows and descendants/media were not migrated. Do checksummed migration and backward-compatibility review first.
- Lifecycle races, shared media byte deletion/revocation, new-partner onboarding, remove/leave/delete space and seven-day account deletion remain disabled.
- Other roots (Contacts, Trips, Occasions, Check-ins/Goals, Places, Letters, Gestures, Items to sort, Links, Days off) still need combined scope/release audit.
- Two-device QA acceptance not done. Production untouched.

## Required gates
1. Flutter analyze/tests green; fix any compilation and integration errors.
2. QA two phones / two accounts: owner-private and pair-shared CRUD with photos and voice.
3. Negative RLS and Storage tests: former partner, unrelated user, stale session, URLs and media access.
4. Close cross-module write routes and legacy-data migration before enabling irreversible lifecycle.

**All relationship/account destructive controls remain disabled.**