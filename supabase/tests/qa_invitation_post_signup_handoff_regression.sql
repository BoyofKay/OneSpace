-- QA only. Exercise the real invitation from the test recipient without changing it.
-- ROLLBACK is mandatory: an accepted invitation must remain available to test.
begin;
do $test$
declare
  pending public.space_invitations%rowtype;
  verified_user uuid;
  old_code text;
  result jsonb;
begin
  select * into pending from public.space_invitations
   where accepted_at is null and revoked_at is null and expires_at>now()
   order by created_at desc limit 1;
  if not found then raise exception 'No active QA invitation to test'; end if;
  select id into verified_user from auth.users
   where lower(email)=pending.invited_email and email_confirmed_at is not null;
  if verified_user is null then raise exception 'No confirmed intended recipient'; end if;
  if exists(select 1 from public.space_members where user_id=verified_user)
    then raise exception 'Recipient is already paired'; end if;

  old_code:=encode(gen_random_bytes(32),'hex');
  insert into public.space_invitations
   (space_id,invited_by,token,expires_at,invited_email,revoked_at,delivery_status,created_at)
   values (pending.space_id,pending.invited_by,old_code,now()+interval '1 day',
    pending.invited_email,now(),'revoked',pending.created_at-interval '1 hour');

  perform set_config('role','authenticated',true);
  perform set_config('request.jwt.claim.sub',verified_user::text,true);
  result:=public.resolve_my_addressed_invitation(old_code);
  if result->>'status'<>'updated' or result->>'code'<>pending.token then
    raise exception 'Replaced invite not resolved for verified recipient';
  end if;
  result:=public.resolve_my_addressed_invitation(pending.token);
  if result->>'status'<>'ready' then raise exception 'Current invitation not ready'; end if;
  perform public.accept_invitation(pending.token);
  if not exists(select 1 from public.space_members
    where user_id=verified_user and space_id=pending.space_id) then
    raise exception 'Recipient was not joined';
  end if;
  if (public.resolve_my_addressed_invitation(pending.token)->>'status')
      <> 'already_joined' then
    raise exception 'Duplicate join did not return already_joined';
  end if;
  if has_function_privilege('anon',
    'public.resolve_my_addressed_invitation(text)','execute') then
    raise exception 'Anonymous invitation status lookup is not blocked';
  end if;
end $test$;
rollback;
select 'PASS: signed-in new recipient, replacement, accept, duplicate and anon denial; all changes rolled back' result;
