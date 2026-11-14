# R30 — Partner Picks, mutual experiences and realtime QA

## Delivered in source
- Each partner can independently set **Interested**, **Maybe**, **Not now**
  or **Clear pick** on a shared experience. Clear pick does not erase partner's choice.
- A **Mutual pick** requires two distinct users each selecting Interested.
- The experience collection shows mutual-pick counts, labels, and an opt-in
  **Show our matches** filter. Archived/completed entries do not count as
  outstanding mutual picks.
- The suggestion card prioritizes jointly selected experiences. Otherwise it
  uses the existing stable daily rotation from the unfinished catalog.
- Realtime subscriptions update partner choices on the collection and detail
  views without overwriting unsent comments and review drafts.
- **No new background push notifications:** changing a preference is a quiet
  relationship decision. Existing FCM gesture, suggestion and comment pushes
  remain untouched.
- The same existing Shared Experiences and Today navigation remains; there is
  no new duplicate module, purchase flow, hidden external content, tracking,
  account switch or migration of old records.

## Backend changes and evidence
- `supabase/schema/0095_r30_shared_experience_partner_interests.sql`
  deployed additively to the existing OneSpace Supabase project.
- New `shared_experience_interests` relation has primary key
  (experience_id,user_id), four constrained choices, RLS and explicit
  column-level grants. The server fills user_id from the Supabase Auth user.
- Partner sees both choices but can update only own choice; cannot
  forge other member's identity or reassign user_id.
- `supabase/tests/0016_r30_partner_interests_rls.sql`: rollback-only
  regression passed on the existing paired test space.
- Security introspection confirms RLS enabled, three policies,
  no authenticated UPDATE grant on user_id and realtime publication.
- Existing Supabase advisor notices for preexisting privileged RPCs
  and Auth leaked-password protection require separate security review;
  they were not introduced by R30.

## Two-device acceptance after a signed preview exists
1. Upgrade installed APK in place; do not uninstall or clear storage.
2. Sign in with the existing two different accounts, preserving the pairing.
3. On phone A open one shared experience, select Interested.
   On B verify "Partner: Interested" without manual refresh.
4. On phone B select Maybe, then Interested. Both phones should show
   Mutual pick automatically, not before the second Interested selection.
5. On A choose Not now. Mutual pick must disappear without changing
   B's preference. Clear pick returns only A to Undecided.
6. Create two mutual picks. Filter the collection by Show our matches
   and test category filter, search, archive and restore interactions.
7. Verify the suggested experience prefers mutual picks; when no mutual
   picks remain, it falls back to unfinished suggestions.
8. Open detail on both phones; make a review draft on A.
   Change the preference on B; A's draft must remain untouched.
9. Complete an experience: it must leave the outstanding mutual count.
   Reopen via the history filter; saved preferences should remain.
10. Verify previously working love-gesture Firebase notification on
    both phones, Reminders, To-do/Checklists, Trips, Notes, and Scrapbooks.
11. Verify no preference operation generates an unexpected push notification.
12. Test Android rotation, large font scaling, offline retry and RTL.

## Release gates
- Full Flutter dependency lock check, analyzer, and unit tests, including
  `experience_interest_rules_test.dart`.
- Signed APK preview with unchanged
  `com.onespace.onespace.preview` application ID, certificate and FCM config.
- Verify GitHub Release asset before distributing; do not mark a source
  change as shipped simply because its test passed.
- Real two-phone acceptance remains necessary even after CI succeeds.
