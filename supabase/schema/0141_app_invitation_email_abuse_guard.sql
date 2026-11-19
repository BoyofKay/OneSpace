-- App invitation emails: private delivery audit and atomic abuse limit.
-- Only the service-role-only Edge Function can reserve a delivery slot.
create table if not exists private.app_invitation_email_sends (
  id bigint generated always as identity primary key,
  sender_id uuid not null,
  space_id uuid not null,
  recipient_digest text not null check (recipient_digest ~ '^[0-9a-f]{64}$'),
  created_at timestamptz not null default now()
);
create index if not exists app_invite_sends_by_sender_time
  on private.app_invitation_email_sends(sender_id,created_at desc);
revoke all on private.app_invitation_email_sends from public,anon,authenticated;
grant select,insert on private.app_invitation_email_sends to service_role;
grant usage,select on sequence private.app_invitation_email_sends_id_seq to service_role;

create or replace function public.claim_app_invitation_email_send(
  p_sender_id uuid, p_space_id uuid, p_recipient_digest text
)
returns boolean
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if current_user <> 'service_role' then
    raise exception 'service role only';
  end if;
  if p_sender_id is null or p_space_id is null
      or p_recipient_digest !~ '^[0-9a-f]{64}$' then
    return false;
  end if;
  -- Sender-level lock serializes competing requests for the same owner.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext('app-invite-mail'),pg_catalog.hashtext(p_sender_id::text)
  );
  if (select count(*) from private.app_invitation_email_sends
       where sender_id=p_sender_id
         and created_at > pg_catalog.now()-interval '1 hour') >= 5 then
    return false;
  end if;
  if exists (select 1 from private.app_invitation_email_sends
       where sender_id=p_sender_id and recipient_digest=p_recipient_digest
         and created_at > pg_catalog.now()-interval '15 minutes') then
    return false;
  end if;
  insert into private.app_invitation_email_sends(sender_id,space_id,recipient_digest)
  values(p_sender_id,p_space_id,p_recipient_digest);
  return true;
end;
$$;
revoke all on function public.claim_app_invitation_email_send(uuid,uuid,text)
  from public,anon,authenticated;
grant execute on function public.claim_app_invitation_email_send(uuid,uuid,text)
  to service_role;
