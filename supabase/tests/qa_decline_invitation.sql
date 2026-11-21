-- QA rollback-only check for 0317.
do $t$
declare a uuid:='db1ac811-6fb0-4f31-8e6c-4e37b5d3a70d'; c uuid:='937e362d-6457-4fe2-b8cd-abad7157a015';
 sp uuid; tok text; failed boolean;
begin
 select id into sp from public.spaces where created_by=a and personal_owner is null limit 1;
 tok:=encode(extensions.gen_random_bytes(32),'hex');
 insert into public.space_invitations(space_id,invited_by,token,expires_at,invited_email)
  values(sp,a,tok,now()+interval '1 hour',(select lower(email) from auth.users where id=c));
 -- Someone else cannot decline it.
 perform set_config('request.jwt.claim.sub',a::text,true);
 failed:=false;
 begin perform public.decline_my_invitation(tok); exception when others then failed:=true; end;
 if not failed then raise exception 'FAIL 1: inviter declined someone else''s invitation'; end if;
 perform set_config('request.jwt.claim.sub',c::text,true);
 perform public.decline_my_invitation(tok);
 if not exists(select 1 from public.space_invitations where token=tok and revoked_at is not null) then
  raise exception 'FAIL 2: invitation still open after decline'; end if;
 if not exists(select 1 from public.account_notices where user_id=a and kind='invitation_declined') then
  raise exception 'FAIL 3: inviter not told'; end if;
 raise exception 'qa_undo';
exception when others then if sqlerrm<>'qa_undo' then raise; end if;
end $t$;
