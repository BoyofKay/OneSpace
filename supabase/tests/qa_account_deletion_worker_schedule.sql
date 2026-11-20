-- Run right after 0310 inside the same transaction (see enable_account_deletion_qa.sql).
savepoint qa_checks;
do $t$
declare u uuid:=gen_random_uuid(); sp uuid; n int; q0 bigint; q1 bigint;
begin
 if not exists(select 1 from private.qa_account_v2_gate where id=1 and enabled) then
  raise exception 'FAIL 1: account gate not enabled'; end if;
 select count(*) into n from cron.job where jobname in ('onespace-qa-shared-media-purge',
  'onespace-qa-account-private-media-purge','onespace-qa-due-account-dispatch');
 if n<>3 then raise exception 'FAIL 2: % of 3 schedules present',n; end if;
 if exists(select 1 from cron.job where jobname='onespace-account-purge') then
  raise exception 'FAIL 2b: legacy account purge still scheduled'; end if;
 select count(*) into n from vault.decrypted_secrets where name in ('onespace_qa_auth_finalizer_secret',
  'onespace_qa_account_purge_secret','onespace_qa_media_purge_secret') and length(decrypted_secret)=64;
 if n<>3 then raise exception 'FAIL 3: worker secrets missing'; end if;
 -- Synthetic due account with an open invitation.
 insert into auth.users(id,aud,role,email,encrypted_password,email_confirmed_at)
  values(u,'authenticated','authenticated','qa-due-'||u||'@example.invalid','synthetic',now());
 insert into public.spaces(created_by,name) values(u,'QA due') returning id into sp;
 insert into public.space_members(space_id,user_id) values(sp,u);
 insert into public.space_invitations(space_id,invited_by,token,expires_at)
  values(sp,u,'qa-due-'||u,now()+interval '48 hours');
 insert into public.account_deletion_requests(user_id,requested_at,purge_after)
  values(u,now()-interval '8 days',now()-interval '1 day');
 select count(*) into q0 from net.http_request_queue;
 n:=private.qa_dispatch_due_account_deletions();
 if n<1 then raise exception 'FAIL 4: due account not dispatched'; end if;
 if exists(select 1 from public.space_invitations where invited_by=u and revoked_at is null) then
  raise exception 'FAIL 5: invitation not revoked at deadline'; end if;
 select count(*) into q1 from net.http_request_queue;
 if q1<=q0 then raise exception 'FAIL 6: finalizer call not queued'; end if;
 -- A cancelled or not-yet-due request is never dispatched.
 update public.account_deletion_requests set purge_after=now()+interval '3 days' where user_id=u;
 update public.space_invitations set revoked_at=null where invited_by=u;
 perform private.qa_dispatch_due_account_deletions();
 if exists(select 1 from public.space_invitations where invited_by=u and revoked_at is not null) then
  raise exception 'FAIL 7: not-due account was touched'; end if;
end $t$;
rollback to savepoint qa_checks;
