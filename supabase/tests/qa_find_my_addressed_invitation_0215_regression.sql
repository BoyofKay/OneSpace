begin;
do $qa$
declare addressed record;user_id uuid;other_id uuid; result jsonb; alternate jsonb; msg text;
begin
 if has_function_privilege('anon',
    'public.qa_find_my_addressed_invitation()','execute')
 or has_function_privilege('anon',
    'private.qa_find_my_addressed_invitation()','execute')
 then raise exception 'Anonymous can discover pending addressed invites';end if;
 select i.token,i.invited_email into addressed
 from public.space_invitations i
 where i.accepted_at is null and i.revoked_at is null and i.expires_at>now()
 order by i.created_at desc limit 1;
 if addressed.token is null then
   raise exception 'Current QA addressed test invitation unavailable';end if;
 select u.id into user_id from auth.users u
 where lower(u.email)=lower(addressed.invited_email)
 and u.email_confirmed_at is not null limit 1;
 select u.id into other_id from auth.users u where u.id<>user_id limit 1;
 if user_id is null or other_id is null then
   raise exception 'QA paired test identities missing';end if;
 perform set_config('role','authenticated',true);
 perform set_config('request.jwt.claim.sub',user_id::text,true);
 result:=public.qa_find_my_addressed_invitation();
 if result->>'status'<>'ready'
 or result->>'code'<>addressed.token
 or (result->>'expires_at')::timestamptz<=now()
 then raise exception 'Intended recipient failed to recover latest valid invite';end if;
 perform set_config('request.jwt.claim.sub',other_id::text,true);
 alternate:=public.qa_find_my_addressed_invitation();
 if alternate ? 'code' then
  raise exception 'Other user discovered a foreign invitation secret';end if;
 if alternate->>'status' not in ('none','already_paired','confirm_email')
 then raise exception 'Incorrect nonrecipient status %',alternate->>'status';end if;
 perform set_config('request.jwt.claim.sub','',true);
 begin
  perform public.qa_find_my_addressed_invitation();
  raise exception 'Unauthenticated discovery unexpectedly worked';
 exception when others then
  get stacked diagnostics msg=message_text;
  if msg<>'Sign in required'
  then raise exception 'Wrong unauthenticated error: %',msg;end if;
 end;
end $qa$;
rollback;
select 'PASS: current confirmed recipient recovers latest QA invite even without link, another account never sees token, anonymous/non-session blocked; rollback' result;