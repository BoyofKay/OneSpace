-- 0327 (28 Nov 2026): fix found by the QA RLS check of 0325.
-- private.fin_permission_guard() was SECURITY DEFINER, so current_user inside
-- it was the function owner and the guard never applied: an owner could set
-- accepted_at on their own grant. The guard now runs as the caller (like
-- private.qa_lock_personal_root_scope), so only fin_answer_permission()
-- (SECURITY DEFINER, grantee only) can accept. QA first; Production at go-live.
create or replace function private.fin_permission_guard()
returns trigger language plpgsql security invoker set search_path to '' as $f$
begin
  if current_user in ('authenticated', 'anon') then
    new.item_id := old.item_id; new.owner_id := old.owner_id; new.grantee_id := old.grantee_id;
    new.created_at := old.created_at; new.accepted_at := old.accepted_at;
    if old.revoked_at is not null then new.revoked_at := old.revoked_at; end if;
  end if;
  return new;
end $f$;
revoke all on function private.fin_permission_guard() from public, anon, authenticated;
