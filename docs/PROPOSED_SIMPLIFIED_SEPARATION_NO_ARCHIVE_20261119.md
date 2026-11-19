> **SUPERSEDED by the founder's confirmed 20 November 2026 requirement:**
> Archive **and restore remain required** for structured private/shared data.
> Uploaded media, photos, voice recordings and documents are excluded.
> This old *no-archive* proposal is NOT approved. See `QA_STRUCTURED_DATA_MILESTONE_20261120.md`.

# OneSpace product scope review: simplify separation without archive generation

Date: 2026-11-19 — founder feedback; **proposal, not implemented deletion authorization**.

## Clarifications
- Risk of deleting a space is **structural for new records too**, not merely old
  QA rows. Many currently writable records have space_id CASCADE and can
  contain private personal content. Deleting QA sample records won't repair it.
- An **external copy saved by the user** and a **downloaded archive file** are
  the same artifact. The UI should say simply **Download archive**; no separate
  redundant "external copy" workflow.
- Founder asked whether OneSpace could **offer no media/content archival or
  restoration**, with an explicit warning. This is technically possible, but it
  is a product-policy change versus the former user-owned archive specification.

## Minimal alternative (if adopted)
1. Protect private data in a user-owned store independent of relationship-space
   cascade deletion, including private attachments, and verify across all
   dependent tables. Private content remains available to its owner.
2. Warn clearly before irreversible separation: old shared records, chats,
   photos, documents and linked files **will be permanently deleted**; they
   cannot be archived or restored by OneSpace. Never silently promise a backup.
3. Offer a deliberate, truthful data export before irreversible deletion.
   Current Download my data is JSON only without actual media; do NOT represent
   it as full-data export. Any download must be user-initiated.
4. After explicit irreversible consent, delete only shared relationship
   metadata and media through Storage API; verify privacy and cleanup.
5. Owner who removes partner receives a clean relationship boundary; invited
   partner becomes unpaired. Owner Delete space leaves both unpaired; personal
   records are retained. Account deletion still needs explicit grace-period
   policy and independent authentication/session cleanup.

**Status:** No account/space/partner deletion enabled, no Production changes,
no QA data hard-deleted, and archive generation remains unimplemented pending
formal decision. Prior archive specs are not silently overridden.
