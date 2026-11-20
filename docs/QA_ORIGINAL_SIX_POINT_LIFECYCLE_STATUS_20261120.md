# OneSpace — original six-point lifecycle plan: status register

**Checkpoint:** 20 November 2026; QA draft [PR #127](https://github.com/BoyofKay/OneSpace/pull/127). This register reflects what has been implemented in code and verified in isolated QA tests, **not** permission to use destructive controls or release an APK.

**Canonical decisions:** Each account permanently owns one private namespace. Each relationship owns a different shared namespace. Unpairing must destroy **all** relationship-owned records and media and preserve each person's private data. Account deletion has a cancellable **seven-day** grace period; then delete the account/private namespace and any current relationship's shared content, leaving the other partner unpaired with their own private content. **No archive or migration to a new solo space.** Approved tagline: **Two of Us. One Space**.

**Status vocabulary:**
- **DONE (QA)** = code/schema exists, QA contract and database regression checks passed; NOT proof of end-to-end device or release.
- **PARTIALLY DONE** = substantial implementation exists, but a required workflow, validation, deployment, or acceptance remains.
- **NOT DONE** = required deliverable not yet implemented or available.
- **DONE DIFFERENTLY** = the intent was met through a safer/approved method different from the original wording.
- **ADDED** = scope discovered while implementing or required to safely complete original points.

## Original requested plan — unambiguous per-point statuses

| Original point | Status | Implemented and verified | Still outstanding |
| --- | --- | --- | --- |
| **1. Notes, To-do/Checklists, Reminders, Calendar private + shared split** | **DONE (QA)** | Previously merged QA schema/UI work; account-owner private vs exact current-couple shared RLS and regression tests, one unified view. | Final two-phone acceptance and release-wide regression. |
| **2. Activities, Memories, Goals/check-ins, Places, Trips, Occasions, Contacts, Letters, Gestures, Items-to-sort, Links, Days off and children** | **PARTIALLY DONE** | QA migrations and rollback tests cover these families, with app cutover for the active screens, account-private photos/docs/voice/share-in and current-pair RLS. All **24 private-capable root tables** audited, **49 child FKs** checked for orphans. | Some modules lack an active Flutter UI (notably Goals); complex child/link/realtime/push flows and real signed URLs and complete two-phone regression remain. Do not classify entire product item as DONE. |
| **3. Remove Partner / Leave Space / Delete Space with warning and irreversible shared deletion** | **PARTIALLY DONE** | Service-gated SQL couple-closure transaction, strict action/actor checks, private preservation, confirmation widget staged, shared media cleanup queue/worker source staged; synthetic A/B→A/C re-pair SQL PASS for Notes and six further modules (Activities, Memories, Goals, Contacts, Trips and Places) under authenticated RLS; legacy personal solo space cannot be deleted by couple actions. | Physical Storage API worker live disposable-file verification, URL expiry, transactional edge cases, concurrency, user-facing control wiring. **Authenticated qa_end_current_relationship RPC implemented and permission-tested behind closed gate; all three buttons still disabled**. |
| **4. Delete Account: seven-day grace, cancel, Auth and data deletion; survivor unpaired** | **PARTIALLY DONE** | QA request/cancel SQL, pending-pair freeze, due-account couple closure for owner and invited partner, old solo cleanup, private-file inventory, retries/claim/ack, final readiness, synthetic SQL Auth FK-cascade and QA-deployed but double-disabled Auth Admin handler with an **atomic one-use finalization claim and 43-table write fence**. **0293** additionally prevents A's Auth deletion while B's shared-upload bytes remain. | Real Storage API byte-delete acceptance, real Auth Admin API, stale-token RPC audit, concurrent HTTP/session tests, scheduling/monitoring, public web request, user-facing submission and deletion buttons. **Account-delete disabled**. |
| **5. Move old personal content to permanent private space; clean QA test data** | **DONE DIFFERENTLY (QA ownership audit) / PARTIALLY DONE overall** | No moves were required for current QA root records: all **24** owner-capable roots passed read-only scan for old solo/mixed scope/creator mismatch; **49** child FK relationships passed orphan audit; transaction-only fixtures leave no records. The new design never relocates private content on separation. | A fresh legacy-data census before enabling deletion, complete dependent-object/media checksum, any actual historical migrations where nonzero rows exist. **Production not migrated or examined; do not interpret zero QA rows as global migration completion**. Existing QA accounts were not bulk-deleted. |
| **6. Remove My Archives; remove three-card unpaired screen** | **DONE (QA source) / PARTIALLY DONE acceptance** | Old My Archives Flutter UI removed; single unpaired Join/invite panel replaces three-card setup in QA source. | Verify invitation and first-sign-in screens with latest QA APK on both phones; past app builds may still have old UI. |
| **Final deliverable: ONE QA build on two phones, Production after approval** | **NOT DONE** | Non-APK GitHub Flutter analysis/tests, invitation and cleanup contract workflows previously green; QA PR remains draft/unmerged. | Finish physical cleanup and Auth acceptance, run the complete latest-head CI, produce one consolidated QA APK, two-phone acceptance and explicit Production approval. |

## Supporting items from the original report

| Topic | Status | What is true now |
| --- | --- | --- |
| **Official tagline** | **DONE (QA source)** | `Two of Us. One Space` canonical; old slogan regression added. |
| **Separate check-your-email sign-up page** | **DONE (source) / PARTIAL device** | New screen exists; older installed QA build cannot prove newest behavior. |
| **Branded QA confirmation email** | **PARTIALLY DONE** | HTML is in repository; actual Supabase Auth → Email Templates configuration and delivery confirmation not verified through this lifecycle. |
| **Invitation accepted / single Join step** | **PARTIALLY DONE** | QA invitation tests passed on prior head; latest two-device acceptance and new onboarding confirmation outstanding. |
| **GitHub billing / QA artifact** | **DONE DIFFERENTLY for CI, not release** | GitHub no-APK workflows run successfully after earlier billing issue; historical R473 is **not** this final lifecycle build. |
| **Google Play web account-deletion requirement** | **NOT DONE end-to-end** | Public site already has a form but contains obsolete shared-retention language. [Website issue #46](https://github.com/BoyofKay/onespace-app/issues/46) tracks it; needs corrected source, translations, verified support flow and safe functional deletion before rollout. |
| **Production data and locks** | **UNCHANGED / OUT OF QA SCOPE** | QA-only schema and source branch; do not treat these tests as Production migrations. No Production mutation authorized. |

## ADDED engineering work discovered during implementation

| Addition | Status | Rationale |
| --- | --- | --- |
| Permanent owner-only Storage buckets for Note/Memory/Trip media, Share-in binary, Activity images/voice; support screenshots included in account cleanup | **ADDED; PARTIALLY DONE** | Prevent old partner file access and Auth deletion blocked by owned objects; worker source and QA endpoints **deployed but unscheduled**; physical byte deletion not acceptance-tested. |
| Shared Storage purge provenance and interrupted uploads | **ADDED; DONE (QA contract)** | Source-guarded queue covers Note, Memory, Trip, Activity, voice and Share-in; interrupted Note/Memory/Trip uploads now queued even when attachment metadata was not committed. Worker not deployed. |
| Pending-delete pairing and post-deadline upload fences | **ADDED; DONE (QA database)** | Blocks new relationships for pending deletion, and new Storage upload/replacement after deadline; rollback tests passed. Multi-session timing acceptance open. |
| Per-user private namespace FK cascade; due Auth preflight, completed-file metadata scrub | **ADDED; DONE (QA database)** | Synthetic SQL Auth cascade passed after fixing 18 root author FKs and audit actor FK; official Auth Admin API never executed. |
| **Six-module authenticated A/B→A/C regression** | **ADDED; DONE (QA rollback)** | After A/B separation and new A/C pairing, C cannot see old couple/shared content across Activities, Memories, Goals, Contacts, Trips or Places, B keeps their private content, B cannot see new A/C Activity. Actual device acceptance remains. |
| **Cross-uploader shared-media finalizer guard (0293)** | **ADDED; DONE (QA regression)** | Reproduced a real safety defect: deletion of A was approved while B's shared image existed. Finalizer now stores erased couple UUID, checks **all** queued files and surviving Storage objects for that couple, and scrubs completed jobs including B's uploads. Both fail-closed and success-with-no-object rollback fixtures passed. |
| Service-only seven-day pipeline orchestration | **ADDED; PARTIALLY DONE** | Staged: close couple → retire old solo → queue private media → await physical purge → final readiness → scrub → Auth delete. QA endpoint deployed **but deliberately unactivated**; both deletion gates OFF, no schedule. |
| External privacy-policy/web-deletion text correction | **ADDED; NOT DONE** | Must correct retired 'survivor keeps shared items' statement across public website locales without releasing misleading copy. |

## Additional QA implementation completed in this continuation

- Migration `0294` creates a service-only **atomic once-only Auth finalization claim** using the same per-user lock as cancellation/pairing; successful readiness and completed job scrubbing are in one transaction. The claim remains sticky on subsequent Auth failures; no unsafe automatic retry.
- The 43 direct authenticated public content tables now carry a DB trigger rejecting owner writes once finalization is claimed; QA rollback proves rejected Notes/Activities/Memories/Contacts and unaffected private writes by the surviving user. Other privileged RPC paths need further audit.
- The QA-only Auth finalizer Edge worker now calls this atomic claim before Auth Admin deletion; HTTP safety/actual Admin deletion remain unverified.
- Both physical Storage API purge Edge workers and the Auth finalizer are **deployed to QA**, with JWT verification and secret guards; none is scheduled. The Auth finalizer has an additional explicit disabled activation condition. **Deployment does not mean activated or end-to-end tested.**
- Migration `0295` provides `public.qa_end_current_relationship`, an authenticated actor+typed-warning RPC guarded by the existing disabled couple-deletion switch. Owner, guest, outsider and wrong-phrase rollback regression passed. The three app CTAs remain disabled.
- Targeted rollback regression rerun after `0294`: **10/10 PASS**, plus new authenticated relationship facade regression PASS; all synthetic inserts rolled back.

## HARD RELEASE GATES (all still open)

1. Deploy and verify shared + private Storage API purge on **disposable** QA files, including signed URL lifetime and retries; no SQL-only simulation counts as physical deletion.
2. Finish full finalizer live testing on disposable QA Auth users, security review, stale session/JWT and two-user simultaneous operations.
3. Finish any missing UI wiring and user-verifiable confirmation text; then and only then enable four destructive controls with explicit QA authorization.
4. Correct and test the website deletion route and branding; no silent Production website release.
5. Run latest CI, produce **one** QA APK, verify A/B→A/C on two phones, then seek explicit Production approval.

**Current safety:** relationship and account backend gates OFF, client deletion submission revoked, four UI actions disabled. No PR merge, no release, no Production changes.
