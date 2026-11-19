-- QA only: securely resolve an addressed invitation after sign-in.
-- An older replaced token may resolve to a newer active invitation ONLY if the
-- signed-in user's email is verified and matches BOTH invitations' recipient.
-- No membership mutation, public token lookup or other-recipient disclosure.
create or replace function private.resolve_my_addressed_invitation(p_token text)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare
  me uuid:=auth.uid();
  verified_email text;
  old_inv public.space_invitations%rowtype;
  valid_inv public.space_invitations%rowtype;
begin
  if me is null then raise exception 'Sign in required' using errcode='28000'; end if;
  select lower(trim(email)) into verified_email from auth.users
    where id=me and email_confirmed_at is not null;
  if verified_email is null then return jsonb_build_object('status','confirm_email'); end if;
  if p_token is null or p_token !~ '^[0-9a-fA-F]{64}$' then
    return jsonb_build_object('status','invalid'); end if;
  select * into old_inv from public.space_invitations
    where token=lower(p_token) limit 1;
  if not found then return jsonb_build_object('status','invalid'); end if;
  if old_inv.invited_email is distinct from verified_email then
    return jsonb_build_object('status','wrong_account'); end if;
  if exists(select 1 from public.space_members
      where user_id=me and space_id=old_inv.space_id) then
    return jsonb_build_object('status','already_joined'); end if;
  if exists(select 1 from public.space_members where user_id=me) then
    return jsonb_build_object('status','already_paired'); end if;
  if old_inv.accepted_at is null and old_inv.revoked_at is null
      and old_inv.expires_at>now() then
    valid_inv:=old_inv;
  else
    select * into valid_inv from public.space_invitations i
      where i.space_id=old_inv.space_id and i.invited_email=verified_email
        and i.accepted_at is null and i.revoked_at is null and i.expires_at>now()
      order by i.created_at desc limit 1;
    if not found then
      return jsonb_build_object('status',
         case when old_inv.accepted_at is not null then 'already_used'
              when old_inv.expires_at<=now() then 'expired' else 'replaced' end);
    end if;
  end if;
  if (select count(*) from public.space_members where space_id=valid_inv.space_id)>=2 then
    return jsonb_build_object('status','full'); end if;
  return jsonb_build_object(
    'status',case when valid_inv.id=old_inv.id then 'ready' else 'updated' end,
    'code',valid_inv.token
  );
end $$;
revoke all on function private.resolve_my_addressed_invitation(text) from public,anon;
grant execute on function private.resolve_my_addressed_invitation(text) to authenticated;
create or replace function public.resolve_my_addressed_invitation(p_token text)
returns jsonb language sql security invoker set search_path=''
as $$ select private.resolve_my_addressed_invitation(p_token) $$;
revoke all on function public.resolve_my_addressed_invitation(text) from public,anon;
grant execute on function public.resolve_my_addressed_invitation(text) to authenticated;
