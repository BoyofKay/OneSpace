# OneSpace QA private vault subset: first real encrypted `.osa` file

> QA only, source prototype. **NOT** a complete OneSpace relationship archive, signed backup, trusted restore, account deletion approval or Production feature. The canonical product tagline remains **Two of Us. One Space**.

## What runs now

- QA migration `0209`: `public.qa_private_vault_subset_manifest()`, signed-in user only. First checks source-to-vault equality, owner membership in exactly one original space, full root/child lineage and the QA schema policy. Returns bounded *real sanitized snapshot JSON strings* for **14 root + 9 child** currently mirrored families, their original PKs and parents, exact PostgreSQL JSON UTF-8 byte lengths, SHA-256 for each snapshot and the independent source-vault aggregate SHA.
- `supabase/functions/_shared/qa_vault_subset_osa.mjs`: verifies source hashes again **before encryption**; produces real binary UTF-8 `.osa` file content with AES-256-GCM ciphertext (random 16B salt + 12B nonce, PBKDF2-HMAC-SHA256 600,000 iterations), authenticated additional data binding original owner, space and full source subset SHA.
- After opening a `.osa`, the verifier checks file/ciphertext size and SHA, AES-GCM authenticity, original owner and space, all source rows, exact SHA and byte lengths, root-parent mapping and original private ownership. Local disk-file roundtrip is exercised by Node 22 GitHub Actions.
- `supabase/scripts/qa_private_vault_subset_export.mjs` provides `exportQaPrivateVaultSubset({url,anonKey,accessToken,passphrase,destination})`. Only the actual **QA** Supabase hostname is accepted, only with a caller-provided authenticated user's token. Password remains local and never appears in RPC requests; output is created with exclusive 0600 permissions and will not overwrite existing files.

## Source format

The authenticated SQL response carries `schema=onespace.qa.private-vault-subset-manifest.v1`, an `owner_id`, original `source_space_id`, `records` sorted by kind/table/source ID, and `subset_sha256`.

Each record contains `kind`, `source_table`, `source_id`, `parent_table`, `parent_id`, `snapshot_json` (the actual PostgreSQL JSONB `::text`), `snapshot_bytes`, and `snapshot_sha256`.

The snapshot SHA is over **exact UTF-8 `snapshot_json` bytes**. The subset digest follows:

```text
SHA256(UTF8("onespace.qa.private.vault-subset.v1|" +
  owner_id + "|" + source_space_id + "|" +
  sorted_records.map(r =>
    r.kind + "|" + r.source_table + "|" + r.source_id + "|" +
    r.snapshot_sha256
  ).join("\n")))
```

The `.osa` envelope includes `format=onespace.qa.vault-subset.osa.v1`, `owner_id`, `source_space_id`, `ciphertext_sha256`, `ciphertext_bytes`, `subset_sha256`, `kdf`, `iterations`, `salt_b64`, `nonce_b64`, and `ciphertext_b64`. The entire manifest is encrypted; user-written notes are not present in the outer file metadata.

## Safety properties

- Original owner and original space are in AES-GCM authenticated data. Wrong password, other owner's ID, other space ID, altered file bytes, record hashes, missing/duplicate children, foreign authorship, orphan checklist items or unreviewed tables cause failure.
- Private content is never silently reclassified as shared. Private-mirror root verification includes every source row, not just records already in the mirror.
- Storage object paths, uploaded documents, images, voice/media identifiers, embedded binary data and direct/indirect document URLs are refused by the client verifier. Native source sanitizer strips known media references while preserving adjacent prose. Media itself is **not recoverable** through this subset.
- The encryption password is known only to the client running export; it is not transmitted to Supabase, embedded in `.osa`, or printed in CI logs.
- This QA endpoint returns **plaintext to the authorized account** over HTTPS before local encryption. Do not log, cache or forward the RPC JSON. This source implementation is **not integrated into Android/iOS** and has **not yet been exercised using an actual QA user token**; test export network calls are mocked.
- Bounds: max 5,000 records, up to 8 MiB source snapshots and 512 KiB per source record; aggregate encrypted file bounded at 20 MiB.

## What this does *not* prove

1. **Completeness**: only 23 mirrored owner-private family types are packaged; the other private-eligible and shared written records are still source-censused, not physically archived.
2. **Server origin**: anyone possessing a passphrase can create a valid encrypted file. AES-GCM authenticity proves integrity under that passphrase, **not** a trusted source-of-truth service signature or authenticated issuance.
3. **Supabase Storage download**: QA-only authenticated staged ciphertext upload, readback verification, owner-only download and 24h cleanup are now deployed via `onespace-qa-subset-file`. This remains a **staged partial file**, not a real `space_archives` lifecycle object; no genuine signed-in user file has yet completed a live QA Storage roundtrip.
4. **Restore**: no transactionally verified private restoration, ID remapping for the other 46 types, replay protection or original-pair shared reference preservation.
5. **Mobile acceptance**: Flutter/iOS/Android UI and two-account device tests are not wired to this prototype. Do not enable partner removal, leave, delete or account deletion.

## Next engineering phases

1. Expand durable per-row manifests to **all eligible written content** within the 69 classified families; keep media/operational exclusions and original-pair author privacy.
2. Provide verified authenticated *server issuance* with immutable source snapshot ID/revision and a cryptographic signature verifiable independently after download. Never store the recovery passphrase on the server.
3. **Staging infrastructure complete (QA 0210–0212)**: now run a real authenticated user's `.osa` upload/download through QA private Storage, and independently verify that downloaded bytes decrypt locally. Then implement the separate trusted `space_archives` issuance path, complete source signatures and real downloader acceptance; staging is not lifecycle readiness.
4. Implement target-space member authorization, transactionality, idempotent ID remapping, private restoration and old shared reference-only history. Run both Android phones and then separately review deletion gates.

CI and QA transactional tests run with temporary synthetic records; all test fixtures must roll back. Do not deploy these QA facilities to Production until the full milestone is accepted.

## QA 0210–0212 staging addendum
- New private internal 24h registry, service-only reservation/verification/lookup/purge, three-file concurrent-safe owner quota, exact owner/UUID Storage paths, dedicated signed-in subset upload/download function and a 24h janitor extension are deployed on QA only.
- Existing client adapter now also supports locally validated `uploadQaPrivateVaultSubset` / `downloadQaPrivateVaultSubset`; recovery passphrase remains client-only.
- All status flags remain nonrestorable and unverified as full lifecycle archives. This is verified **ciphertext transport/storage integrity**, not authoritative **source provenance** or full record coverage.
- See [QA Subset Encrypted Storage Staging](QA_SUBSET_ENCRYPTED_STORAGE_STAGING_20261120.md).
