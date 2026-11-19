# QA-only encrypted .osa Storage staging

**OneSpace: Two of Us. One Space**

This QA feature stages encrypted owner-private **subset** files. It is not an archive-issuance protocol, a full backup, a trusted restoration, or a deletion/unpairing authorization.

## Live QA deployment

- QA project only: `ugwrpeduzyzrujkizqfo`
- Edge Function `onespace-qa-subset-file` (JWT required, v1), `POST ?action=upload&source_space_id=<uuid>` with `application/octet-stream` body containing the locally encrypted `.osa` file
- Edge Function `onespace-qa-subset-file`, `POST ?action=download&staging_id=<uuid>` with signed-in bearer token, returns `application/octet-stream` only to original owner after verifying actual Storage bytes
- `onespace-archive-janitor` (v3, existing cron secret required) safely clears failed/expired records and exact Storage object keys, separately from the real 30-day lifecycle archive list

All endpoints reject accidental Production environment targeting. Do not transmit passphrases to Edge Functions or the Supabase RPC. Only the local encryption/decryption client needs the recovery secret.

## Upload authorization and integrity sequence

1. Client obtains `public.qa_private_vault_subset_manifest()` using its current signed-in QA access token (14 private roots + 9 private dependents only).
2. Client validates all PostgreSQL source row hashes and owner/parent relationships, encrypts the content with AES-256-GCM/PBKDF2 to a real `.osa` file.
3. Client checks the file again locally using `decryptVaultSubsetFile` and sends only ciphertext bytes + its existing Supabase bearer token to QA.
4. QA JWT gateway and Edge Function check the identity against `/auth/v1/user`. Staging service verifies original space membership, restricts **three active files per owner**, assigns path `owner/qa-subsets/staging-id.osa`.
5. Edge Function checks `.osa` envelope owner, source space, unverified/non-restorable flags, encryption algorithm, ciphertext length and ciphertext SHA-256. **This is only ciphertext-envelope integrity, not verified archive origin or full source completeness.**
6. Service writes to existing private `onespace-archives` bucket with `x-upsert=false`, immediately reads back from private Storage and validates complete length and SHA-256 **before** making the staging record `available`.
7. Download checks original owner and unexpired status, rereads the private object, checks actual length/SHA-256 again, and returns encrypted bytes. Client verifies ciphertext, AES-GCM authentication and all source record hashes before it accepts the file.

## Schema separation and expiry

- Internal table: `private.qa_vault_subset_staging` (RLS enabled, no public Data API access).
- Service-only RPCs: `qa_subset_reserve_service`, `qa_subset_mark_available_service`, `qa_subset_lookup_service`, `qa_subset_mark_failed_service`, `qa_subset_due_purge_service`, `qa_subset_finish_purge_service`.
- `available` means **byte-for-byte readback of staged encrypted material verified**, NOT a real/restorable archived relationship. DB CHECK constraints require `is_verified_archive=false`, `can_restore=false`. No `space_archives` record is created or marked `ready`.
- Expiry: 24 hours. Failed and expired objects are deleted under explicit owner/UUID path rules. Pending reservations older than 10 minutes are cleanup-eligible. Never call lifecycle account-delete, leave or partner-removal code.
- Per-user advisory transaction locks prevent concurrent reservations from bypassing the three-file quota.
- The QA-only staging table is in `private` schema so the 69 registered **public source family** catalog remains fail-closed for future unreviewed app data.

## Verification and limits

- 59 Node22 tests passed across the encrypted file, RPC mocked-auth adapter, real handler mock Storage upload/readback/download, same-size tamper, account ownership, janitor expiry and existing archive safety regressions.
- QA SQL 0210 test covers service-only permissions, exact owner path, state transitions, anti-replay, quota, expiry and partner denial with a transaction rolled back.
- **No actual end-user JWT was available to run a live QA Storage upload/download**. QA deployment is active and handler/mock tests passed, but live signed-in app acceptance remains required.
- Server reads encrypted `.osa` bytes only; the key/password never leaves the user client. Neither envelope integrity nor user-controlled encryption proves origin from OneSpace's authoritative database. A server-attested source manifest and fully captured 69-family written content remain required.
- This prototype is Node/JavaScript; integration into Flutter/Android/iOS and independently verified external backups is not yet shipped. Media, audio, photos, videos, uploaded documents and indirect file references remain excluded.
