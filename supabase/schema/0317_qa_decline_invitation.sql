-- QA 0317 (Amr, 21 Nov): an existing account with no space must accept or
-- decline an invitation (no automatic join). Declining ends the invitation
-- and tells the inviter with a banner on their Today screen.
alter table public.account_notices drop constraint if exists account_notices_kind_check;
alter table public.account_notices add constraint account_notices_kind_check check (kind in
 ('partner_left','you_left','partner_removed_you','you_removed_partner','space_deleted',
  'you_deleted_space','partner_deleted_account','invitation_declined'));

create or replace function public.decline_my_invitation(p_token text)
returns void language plpgsql security definer set search_path to '' as $function$
declare me uuid:=auth.uid(); my_email text; inv record;
begin
 select lower(u.email) into my_email from auth.users u where u.id=me;
 if me is null or my_email is null then
  raise exception 'Sign in required' using errcode='42501';
 end if;
 select i.id,i.invited_by,i.invited_email into inv from public.space_invitations i
  where i.token=p_token and i.accepted_at is null and i.revoked_at is null
    and i.expires_at>now()
  for update;
 if not found then return; end if;  -- already gone: nothing to decline
 if lower(coalesce(inv.invited_email,'')) is distinct from my_email then
  raise exception 'This invitation belongs to another email address' using errcode='42501';
 end if;
 update public.space_invitations set revoked_at=now() where id=inv.id;
 insert into public.account_notices(user_id,kind,title,body) values(inv.invited_by,
  'invitation_declined',private.qa_first_name(me,'Your invitee')||' declined your invitation',
  'You can invite them again or invite someone else from My Space.');
end $function$;
revoke all on function public.decline_my_invitation(text) from public,anon;
grant execute on function public.decline_my_invitation(text) to authenticated;
