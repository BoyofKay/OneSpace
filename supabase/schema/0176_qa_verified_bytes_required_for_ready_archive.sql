-- QA 0176: a "ready" or retired archive must have independently verified
-- encrypted bytes, not merely a filename and a purported SHA-256 string.
-- Production and live content are never changed by this migration.
do $guard$
begin
 if exists(select 1 from public.space_archives
      where status in ('ready','purge_due','purged')
        and encrypted_bytes_verified is distinct from true) then
   raise exception 'Existing unverified archive must be reconciled before strengthening readiness';
 end if;
end $guard$;
alter table public.space_archives drop constraint ready_archives_complete;
alter table public.space_archives add constraint ready_archives_complete check (
  status not in ('ready','purge_due','purged')
  or (
    ready_at is not null and expires_at is not null
    and encrypted_object_path is not null
    and ciphertext_sha256 ~ '^[0-9a-f]{64}$'
    and byte_length > 0
    and encrypted_bytes_verified is true
  )
);
-- This does not set ready, generate files, encrypt records or enable deletion.
