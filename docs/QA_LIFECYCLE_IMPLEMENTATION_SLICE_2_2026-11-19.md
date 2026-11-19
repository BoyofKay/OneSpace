# OneSpace QA lifecycle — second safe implementation slice (2026-11-19)

This is a **QA-only** implementation milestone. Production untouched.

## Decision locked
Automatic backup into **OneSpace installed-app private files** does **not** trigger archive deletion. After an explicit user-initiated **Save archive to Downloads**, Android reads the written file back and verifies SHA-256 before the authenticated backend can mark that recipient's individual archive for deletion. If not explicitly downloaded, an archive expires 30 days after **ready_at**. The hourly archive janitor removes due encrypted files through Supabase Storage API; database keeps minimal audit metadata (without archive content). Other recipient's archive independently retained.

## Implemented
- Private Supabase archive bucket, per-recipient per-type archive metadata with strict RLS (read own metadata only).
- Public acknowledgement requires signed-in matching recipient, ready/not-expired archive and identical SHA-256; anonymous cannot acknowledge, no ack from automatic app-private download.
- QA authenticated archive-download Edge Function checks recipient's JWT and owner-bound Storage path before streaming encrypted bytes.
- Android My Archives: automatic encrypted app-private copy (removed on uninstall, Android app backup disabled), and explicit manual save to Downloads with native readback checksum before acknowledgement. No confirmation popup containing form fields.
- Hourly service-secret archive janitor deletes only temporary archive Storage objects after explicit verified external download or 30-day TTL, not shared/private live objects.
- Read-only separation preflight counts space-linked records and marks destructive workflow not yet safe.
- QA legacy account deletion request/purge disabled to prevent old behavior deleting records before shared-space export/cleanup.
- Added unit tests for app-private exclusion, explicit external success, and 30-day expiry.

## Not implemented yet — must NOT be misrepresented as complete
- Real encrypted media-inclusive archive **generation and delivery** (registry currently has no ready archives).
- Email to each partner when archive ready.
- Private Vault migration from existing tables and safe detach of historic shared references.
- Active live space retirement, remove partner, leave and Delete space.
- Account deletion cascades/recovery; restore-from-archive.
- iOS external save proof and full iOS archive handling.
- Readiness worker for large exports and retries; notifications.
- End-to-end real-account and media-integrity QA.

## Safety verification
- The archive bucket is private; no direct client Storage policy.
- No user archive rows or existing shared/private data mutated.
- 30-day expiry starts at ready_at; hourly cleanup scheduled.
- No production schema, code release or worker touched.
- Real account deletion remains unavailable in QA pending the new lifecycle.

## QA testing this slice
My Profile > My Space > My Archives shows empty state with policy; My Space > Check separation readiness runs a read-only safety check. Existing invitation and password QA tests remain available. Archive download buttons appear only for genuine server-ready encrypted archive rows; none are fabricated.
