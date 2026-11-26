-- 0323 (26 Nov 2026, owner UAT decision D105): the person who sent an app ticket sees
-- its status, outcome and a reply written for them by support (Me → Your messages).
-- The Command Center keeps a separate INTERNAL note (resolution_note) and the name of
-- who changed it (status_changed_by); people can no longer read those two columns.
-- Website tickets have no in-app view; support answers them by email.
-- QA first. Production with the owner's approval (the Command Center uses both).

alter table public.support_requests
  add column if not exists support_reply text check (char_length(support_reply) <= 2000),
  add column if not exists support_reply_at timestamptz;

-- People read their own tickets (RLS support_requests_select_own) but only these columns.
revoke select on public.support_requests from authenticated;
grant select (id, user_id, kind, subject, message, reply_email, app_version, platform, locale,
  diagnostics, status, created_at, screenshot_path, outcome, status_changed_at,
  support_reply, support_reply_at) on public.support_requests to authenticated;

-- Same key check, rules and log as 0322, plus the reply for app tickets.
-- The 0322 version (7 arguments) stays so an older Command Center keeps working; it never
-- touches the reply.
create or replace function public.ops_set_support_status(
  p_key text, p_channel text, p_id uuid, p_status text, p_outcome text, p_note text, p_by text,
  p_reply text)
returns jsonb language plpgsql security definer set search_path to '' as $f$
declare result jsonb; old_reply text;
begin
  if char_length(coalesce(p_reply, '')) > 2000 then
    raise exception 'invalid request' using errcode = '22023';
  end if;
  if p_channel <> 'app' and nullif(btrim(coalesce(p_reply, '')), '') is not null then
    raise exception 'website tickets are answered by email' using errcode = '22023';
  end if;
  -- Key check, validation, status/outcome/note update and the log.
  result := public.ops_set_support_status(p_key, p_channel, p_id, p_status, p_outcome, p_note, p_by);
  if p_channel = 'app' then
    select support_reply into old_reply from public.support_requests where id = p_id;
    update public.support_requests
      set support_reply = nullif(btrim(coalesce(p_reply, '')), ''),
          support_reply_at = case
            when nullif(btrim(coalesce(p_reply, '')), '') is null then null
            when old_reply is distinct from nullif(btrim(coalesce(p_reply, '')), '') then now()
            else support_reply_at end
      where id = p_id;
  end if;
  return result || jsonb_build_object('reply', nullif(btrim(coalesce(p_reply, '')), ''));
end $f$;
revoke all on function public.ops_set_support_status(text, text, uuid, text, text, text, text, text) from public, authenticated;
grant execute on function public.ops_set_support_status(text, text, uuid, text, text, text, text, text) to anon;
