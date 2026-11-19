# OneSpace — QA lifecycle implementation, first safe slice

Date: 2026-11-19
Branch: qa/lifecycle-first-slice-20261119
Target: signed Android QA APK only. No Production build or deployment.

## Implemented in this QA slice
- Change password moved from large form dialog to full page with Current/New/Confirm and Send a reset email link below.
- Today Invitation CTA renamed Invite my partner and opens full-page email entry.
- Recipient email, expiry and delivery state stored under invitation record.
- Invite disabled until valid email; recipient's matching verified account is required to accept.
- QR, formatted code with copy icon, status, SMS/WhatsApp sharing, same-code resend and confirmation before replacing/revoking on full page. No raw long link displayed.
- QA backend RPC create_addressed_invitation enforces creator-only, 2-member capacity, one code per recipient and replacement confirmation.
- QA backend RPC accept_invitation compares signed-in user's VERIFIED email with stored invitation recipient. Also applies to manual/QR joins.
- QA email Edge Function enforces stored recipient before sending, updates provider-accepted status; production function unchanged.
- Pending deep link can automatically attempt pairing after signup/email verification; backend remains authority.
- Profile My Space view shows role and member count.

## Deliberately NOT enabled because unsafe before archival
- Partner leave/removal; owner deletion/continuation; higher-order account deletion changes.
- Shared-media destruction; archive TTL cleanup; backup import/export/restore.
- Reason: 33 tables cascade delete by space_id, and some mix private and shared items.

## Decisions to resolve before enabling deletion
- P01: whether an app-private-only download qualifies as successful server-delete trigger. Conservative interim rule: NO, and no automatic server purge is implemented.
- Portable archive encryption and recovery key strategy after reinstall.
- Grace-period/cancellation behavior for owner Delete account.
- Verified personal-vault migration, shared/private classification, media integrity.

## Required QA tests
1. Change-password fields and plain reset link on full subpage, no popup.
2. Invite button disabled until valid recipient.
3. Recipient email stored; status, QR, code and copy shown.
4. Re-send same code and original expiry; replacement/revoke requires input-free confirmation.
5. Verified B email from link/QR/manual joins A; different verified email rejected.
6. New signup + verification can use preserved incoming invite; old unaddressed code rejected in QA.
7. My Space identifies owner vs partner but exposes NO dangerous destructive action.
8. Production remains unmodified.

Next implementation gate: user-owned Private Vault, media-inclusive verified per-user encrypted exports, safe asynchronous cleanup and restore, then leave/remove/delete.
