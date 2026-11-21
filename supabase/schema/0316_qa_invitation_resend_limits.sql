-- QA 0316 (Amr, 21 Nov): resending an invitation or sending a replacement
-- code was refused for 15 minutes. Allow the same recipient again after one
-- minute (still blocks double taps) and up to 10 emails an hour per sender.
create or replace function public.claim_app_invitation_email_send(
 p_sender_id uuid, p_space_id uuid, p_recipient_digest text)
returns boolean language plpgsql set search_path to '' as $function$
begin
  if current_user <> 'service_role' then
    raise exception 'service role only';
  end if;
  if p_sender_id is null or p_space_id is null
      or p_recipient_digest !~ '^[0-9a-f]{64}$' then
    return false;
  end if;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext('app-invite-mail'),pg_catalog.hashtext(p_sender_id::text)
  );
  if (select count(*) from private.app_invitation_email_sends
       where sender_id=p_sender_id
         and created_at > pg_catalog.now()-interval '1 hour') >= 10 then
    return false;
  end if;
  if exists (select 1 from private.app_invitation_email_sends
       where sender_id=p_sender_id and recipient_digest=p_recipient_digest
         and created_at > pg_catalog.now()-interval '1 minute') then
    return false;
  end if;
  insert into private.app_invitation_email_sends(sender_id,space_id,recipient_digest)
  values(p_sender_id,p_space_id,p_recipient_digest);
  return true;
end;
$function$;
