-- QA 0215: address a valid invitation to its EMAIL-VERIFIED recipient
-- even when the browser-to-app deep link was lost during sign-up/sign-in.
-- Current user only; never lists other recipients or old couple history.
create or replace function private.qa_find_my_addressed_invitation()
returns jsonb language plpgsql stable security definer set search_path='' as $fn$
declare
  me uuid:=auth.uid();
  confirmed_email text;
  candidate public.space_invitations%rowtype;
begin
  if me is null then raise exception 'Sign in required' using errcode='28000';end if;
  select lower(btrim(u.email)) into confirmed_email
  from auth.users u where u.id=me and u.email_confirmed_at is not null;
  if confirmed_email is null
  then return jsonb_build_object('status','confirm_email');end if;
  if exists(select 1 from public.space_members sm where sm.user_id=me)
  then return jsonb_build_object('status','already_paired');end if;
  select i.* into candidate
  from public.space_invitations i
  where lower(btrim(i.invited_email))=confirmed_email
    and i.invited_by<>me
    and i.accepted_at is null and i.revoked_at is null
    and i.expires_at>now()
    and exists(select 1 from public.space_members owner_member
      where owner_member.space_id=i.space_id
        and owner_member.user_id=i.invited_by)
    and (select count(*) from public.space_members current_members
         where current_members.space_id=i.space_id)<2
  order by i.created_at desc limit 1;
  if not found then return jsonb_build_object('status','none');end if;
  return jsonb_build_object('status','ready',
    'code',candidate.token,
    'expires_at',candidate.expires_at);
end $fn$;
revoke all on function private.qa_find_my_addressed_invitation()
 from public,anon,authenticated;
grant execute on function private.qa_find_my_addressed_invitation()
 to authenticated;

create or replace function public.qa_find_my_addressed_invitation()
returns jsonb language sql stable security invoker set search_path='' as $fn$
  select private.qa_find_my_addressed_invitation()
$fn$;
revoke all on function public.qa_find_my_addressed_invitation() from public,anon;
grant execute on function public.qa_find_my_addressed_invitation()
 to authenticated;
