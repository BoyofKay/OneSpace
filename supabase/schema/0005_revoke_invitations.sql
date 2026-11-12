-- Allow a member to revoke an outstanding invitation without creating a replacement.
create or replace function private.revoke_pending_invitation(p_space_id uuid)
returns integer language plpgsql security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_count integer := 0;
begin
  if v_user is null or not private.is_space_member(p_space_id) then
    raise exception 'Shared space not found';
  end if;
  -- Lock parent before modifying invitation rows, matching other pairing RPCs.
  perform 1 from public.spaces where id = p_space_id for update;
  update public.space_invitations
  set revoked_at = now()
  where space_id = p_space_id
    and invited_by = v_user
    and accepted_at is null
    and revoked_at is null
    and expires_at > now();
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

create or replace function public.revoke_pending_invitation(p_space_id uuid)
returns integer language sql security invoker set search_path = ''
as $$ select private.revoke_pending_invitation(p_space_id); $$;

revoke all on function private.revoke_pending_invitation(uuid) from public, anon, authenticated;
grant execute on function private.revoke_pending_invitation(uuid) to authenticated;
revoke all on function public.revoke_pending_invitation(uuid) from public, anon;
grant execute on function public.revoke_pending_invitation(uuid) to authenticated;
