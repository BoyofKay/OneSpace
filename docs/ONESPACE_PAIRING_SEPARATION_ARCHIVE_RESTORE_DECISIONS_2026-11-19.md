# OneSpace — Pairing, Separation, Archive, and Restore Decisions

**Recorded:** 19 November 2026  
**Status:** Product decision and handover record; **not an authorization to implement**.  
**See also:** The full downloadable handover `OneSpace_Pairing_Separation_Archive_Restore_Decisions_2026-11-19.md` provided in the ChatGPT conversation (196 lines, including detailed acceptance tests and open decisions).

> **Newest correction overrides earlier proposals:** Automatically downloaded encrypted archives must live in **OneSpace's installed-app private file storage**, not in the public Files/Downloads area. They **disappear when the app is uninstalled**. Independently, the user receives an email with an authenticated archive download link and can deliberately save a durable external copy. Temporary server archives are deleted upon **verified successful download or after 30 days**, whichever occurs first. **Decision 19 Nov: only an explicit USER-INITIATED external archive download/save, completed and verified, triggers early deletion. An automatic copy to app-private storage NEVER triggers server deletion.**

## Confirmed product decisions

1. **No new Remember me checkbox.** Continue secure persisted sessions, OS biometric/device unlock, and Google/Apple password managers; no storing recoverable passwords inside OneSpace.
2. **No input popups.** All form entry and multistep workflows occur on full subpages. Use confirmation popups only, with no text fields.
3. **Change password:** Subpage, exactly current password, new password, confirm new password; do not show account email. Plain-text **Send a reset email** CTA appears after the three inputs.
4. **Invite my partner:** Replace invitation CTA label; show a dedicated full page asking for B's email. Invite is disabled until valid email. Backend saves recipient email, invitation status and code; sends branded email from `invitations@onespace.live`. Show QR and formatted copyable code on A's page (no raw invitation URL). Disable Invite after submission; allow status/resend same code/replacement with confirmation/revoke. Today continues to show the compact invitation card.
5. **Invited recipient B:** Email includes clickable invitation, OneSpace logo, proper tagline and official app store icons/badges. Badge links only if valid/applicable; otherwise nonclickable. App link opens installed OneSpace, or install/manual-code fallback if absent. After signup/signin and verified email, automatically join the original owner's existing space; QR and manual code also work. The backend must verify B's authenticated verified email equals the intended recipient, including for QR/manual entry.
6. **Space permissions:** Original owner A **cannot leave**, cannot transfer ownership, and may **Remove partner** or **Delete space**. Invited B may **Leave space** only. Add **My Space** under Profile immediately before Change password. Separation and deletion actions need a simple confirmation popup.
7. **Owner continuity after B leaves or is removed:** A keeps the same OneSpace experience and can invite C **without creating a space manually**. Backend internally establishes a fresh relationship-space boundary (potentially new internal ID) carrying only A's personal/private data. C can never see B's old shared content, notifications, attachments or pending actions. This is a UI continuity rule, **not permission to reuse old relationship history**.
8. **Invited B after leaving/removal:** Becomes unpaired, keeps own private account/data, can create a space or join another person.
9. **Owner Delete space:** Both users become unpaired and keep private accounts/data. Distinguish from Remove partner: do **not** automatically re-create a shared space after deliberate Delete space unless separately approved.
10. **Private versus shared:** Personal/private notes, contacts, reminders, memories, attachments etc. belong to their original account and survive separation. Old relationship shared objects/media are archived for each entitled partner, then removed from live backend when safe. Any old shared reference within a private item becomes harmless, inert, non-navigable historical text.
11. **Archive composition:** Each entitled user receives own private-data archive and an authorized old shared-history archive, with actual files/media and integrity information. Do **not** include the other partner's private records. **Only private archives can ever be restored**; old shared-history archives are reference-only.
12. **Archive locations:** (a) automatic encrypted local copy inside **installed OneSpace app private files** (lost on uninstall); (b) temporary, private encrypted **backend archive object**; (c) optional durable external copy **deliberately saved by user** through emailed authenticated download link. No email ZIP attachments/public permanent links. Email notifies each partner of archive readiness.
13. **Archive cleanup:** Delete temporary server archive objects after verified successful download or at 30 days, whichever is earlier. No indefinite cloud archives. Ensure recipient-specific and race-safe cleanup. Explicit user download/save with verification—not automatic app-private save—triggers early purge; otherwise purge after 30 days. App-local archive and deliberately saved external archive are distinct.
14. **Live storage cleanup:** Once entitled archives are actually verified and the safety gate is met, delete old shared database records **and actual Storage files via Storage API**, not SQL-only Storage metadata deletion. Retain private records and attachments. Maintain only legally/operationally necessary audit status.
15. **Restore private data:** Preferred automatic continuity via user-owned Personal Vault when same account joins another space; no import if data already exists. Where recovery is needed after joining, offer a **full restore subpage** from (a) this installed app's private archive, (b) server archive if still retained, or (c) manually selected user-saved external archive. Validate cryptographic authenticity, identity/account ownership, integrity, archive type and per-record privacy; dedupe and show real progress. Private remains private. Shared content must never enter a new relationship.
16. **Delete account cascades:** Owner A's Delete account must automatically orchestrate space retirement, exports, notifications and cleanup before account deletion. No separate manual Delete space step. B's Delete account similarly performs a B-leave path so A continues in a clean private-only context. Existing account-deletion grace period requires reconciliation.
17. **Notifications:** Both receive account-level in-app notifications and email for leave/remove/delete/export. Do not store lifecycle notifications solely under a space that will be deleted.

## Suggested end-to-end actions

### Invite
A opens **Invite my partner** → enters partner email → Invite → backend persists recipient and invitation securely → email sent/status recorded → A sees QR + copyable manual code, Close → B opens link, installs if necessary, authenticates and verifies email → backend checks recipient identity, code validity and membership → B joins current relationship exactly once → both get confirmation.

### B leaves / A removes B
Confirmation-only dialog → persist separation request / block old shared writes and invitations → retain both users' private data and media → make per-user private/shared archive snapshots and verify → prepare app-private automatic downloads and email download links → delete active shared records/media safely → A silently transitions to clean owner space and can invite C; B is unpaired → per-user server archives expire on successful download (trigger pending) or at 30 days → app-local copies remain until app uninstall, externally saved copies persist under user's control.

### A deletes space
Same export/cleanup/notification protections → both accounts become unpaired, private data stays → do not create replacement space automatically.

### A deletes account / B deletes account
Higher-level account deletion invokes respective space-close / B-leave sequence automatically. Grace-period cancellation semantics and how a deleted account authenticates to retrieve an archive remain open.

### Restore into later space
User joins/creates new relationship → if user's private data already exists, continue with no duplication → if recovery needed, offer installed-app private backup, still-available server backup, or Choose archive → validate user/signature/integrity and private-only entries → import privately, detach old shared references, display progress/errors → no old shared content can be restored into the new relationship.

## Archive rules — critical distinction

| Location | How created | Removal | Survives uninstall? |
| --- | --- | --- | --- |
| App-private installed OneSpace files | Automatic encrypted download | App uninstall / app-data removal (plus any separately approved cache policy) | **No** |
| Private temporary server archives | Backend export job | **Successful verified download OR 30-day deadline**, first event; **explicit user-initiated, verified external download** | Only until server purge |
| External user-saved archive | User follows authenticated email link and saves deliberately outside app | User controls own copy | **Yes, if actually saved outside app** |

**Loss warning:** The automatic app-private copy MUST NOT cause backend archive deletion. The user-initiated external download must finish saving and pass integrity verification before cleanup can begin. The user must be told that the archive will be removed from the server after that action.

## Verified existing-system findings (read-only QA/repository investigation)

- Current `spaces.created_by` captures creator; `space_members` maps account to relationship.
- **33 direct tables** have a `space_id` foreign key with `ON DELETE CASCADE`; many contain mixed private/shared items. Direct space deletion would risk deleting private data. Separate user-owned Personal Vault before destructive changes.
- Current `Download my data` (`lib/features/settings/account_data_screen.dart`) exports JSON via `export_my_data` and saves to phone Downloads; **not** the proposed encrypted archival system, media-inclusive export, or app-private temporary archive.
- `space_notifications` are space linked and would be lost under cascade; add account-scoped lifecycle notifications.
- Supabase Storage contains activity media/voice, memory photos, note images and trip documents. SQL-only deletion from Storage metadata is insufficient; Storage API must remove actual objects.
- Current account deletion has a **seven-day grace period** requiring explicit integration into high-level cascading Delete account.
- Secure session / device unlock already exist; no new Remember me feature.

## Pending decisions (NOT settled)

- **P01 RESOLVED 19 Nov:** Only a deliberate user-initiated archive download to a user-chosen external location, after confirmed save and checksum verification, triggers early server deletion. Automatic app-private downloads never count. The 30-day deadline remains the fallback. Each recipient and archive type is independent.
- **P02:** Whether to expose an additional **Save external copy** CTA inside the app and warn before server copy is purged.
- **P03:** Exact start of the 30-day countdown (separation, archive creation, or user notification) and reminder cadence.
- **P04:** Local app-private archive growth, quotas and user-initiated local cleanup; is it kept until uninstall by default?
- **P05:** Portable encryption/recovery credential policy for user-saved external files after reinstall/device loss; account-bound signature validation.
- **P06:** Canonical data classification and migration of mixed private/shared rows and linked attachments.
- **P07:** Owner-continuity implementation: personal workspace + fresh relationship ID versus backend copy of private content; preserve invisible UX.
- **P08:** Seven-day account deletion grace period, timing of separation, cancellation effects, and archive download access after account deletion.
- **P09:** Handling partner offline/undeliverable email through 30-day expiry, irreversible loss warning.
- **P10:** Durable export queue, chunking, retry and integrity validation, encryption, Storage limits/cost, and provider failures.
- **P11:** Exact UI after explicit owner Delete space versus owner Remove partner.
- **P12:** Verified Android/iOS App/Universal Links, QR/manual recipient checks, official store URLs and invitation delivery statuses.
- **P13:** Audit/legal/backups retention exceptions versus removal of active data and temporary archives.
- **P14:** Restore prompting only for missing data; progress/duplicates/partial import handling.

## QA acceptance checklist (when authorized)

- A invites B with validated email; invite cannot be redeemed by another email, duplicate/expired/revoked codes fail.
- B signs up/verifies and joins once, including link/QR/manual code and app restart.
- A removes B or B leaves → owner stays in continuous private-only OneSpace and can invite C immediately; no old shared data actions/notifications remain.
- A deletes space → both unpaired with private data; owner is not silently auto-repaired.
- Old-space shared data/media included in authorized exports and deleted using Storage API once safe; personal data retained.
- App-private archives are present while installed, **lost after uninstall**; external copies users deliberately saved remain accessible; server archive success/30-day purge is verified according to resolved P01.
- Only account-authentic private data restores from app-local/server/manual archive; shared content and other user's data fail verification. Old shared links inert; duplicated imports safe.
- Owner account deletion cascades without requiring separate manual space deletion, and invited partner is correctly unpaired.
- Confirm UI has no data-entry popup, owner Leave/Transfer actions do not exist, no new Remember me checkbox.

## Implementation order — proposal only

1. Finalize P01, 30-day retention clock, portable archive key policy and data classification.
2. Refactor schema and ownership so private data/media survive space retirement.
3. Build encrypted per-user archives, integrity checks, background jobs, account-level notifications, app-private auto-copy, external authenticated email download, and lifecycle purge.
4. Build secure role-based leave/remove/delete and owner's continuous clean relationship context.
5. Build private-only archive restoration and integration into higher-level Delete account.
6. Build subpage-only UX and recipient-specific invitation/verified-email auto-pairing.
7. Exercise complete QA lifecycle on disposable data + real media, including failure conditions, and review Production security before release.

---

**Handover:** This file records current decisions and explicit open questions. **No database, app, user-account, or storage changes are authorized by this document.** When resuming work, **read this first; P01 is resolved: only verified user-initiated external save counts toward early purge**.
