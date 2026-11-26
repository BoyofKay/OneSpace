-- 0322 (26 Nov 2026, owner decision D101): support tickets can be closed with an outcome.
-- The Command Center (server side) sets status, outcome and a short internal note on
-- app tickets (support_requests) and website tickets (public_support_requests).
-- It is the Command Center's only database change, through ONE function that works
-- only with a dedicated key. Only a SHA-256 hash of that key is stored here; the key
-- itself lives in Cloudflare (SUPPORT_OPS_KEY_QA / SUPPORT_OPS_KEY_PRODUCTION).
-- Every change is logged. QA first; Production at the next go-live.

alter table public.support_requests
  add column if not exists outcome text check (outcome in ('solved','not_a_bug','feature_request','duplicate','no_reply','other')),
  add column if not exists resolution_note text check (char_length(resolution_note) <= 1000),
  add column if not exists status_changed_at timestamptz,
  add column if not exists status_changed_by text check (char_length(status_changed_by) <= 200);
alter table public.public_support_requests
  add column if not exists outcome text check (outcome in ('solved','not_a_bug','feature_request','duplicate','no_reply','other')),
  add column if not exists resolution_note text check (char_length(resolution_note) <= 1000),
  add column if not exists status_changed_at timestamptz,
  add column if not exists status_changed_by text check (char_length(status_changed_by) <= 200);

-- The hash of the Command Center key (one row). Set by the owner, never by the app.
create table if not exists private.support_ops_key (
  id int primary key default 1 check (id = 1),
  key_sha256 text not null check (key_sha256 ~ '^[0-9a-f]{64}$'),
  set_at timestamptz not null default now()
);
revoke all on private.support_ops_key from public, anon, authenticated;

-- Who changed what, when (no message content).
create table if not exists private.support_status_log (
  id bigint generated always as identity primary key,
  channel text not null check (channel in ('app','website')),
  request_id uuid not null,
  old_status text, new_status text not null, outcome text,
  changed_by text not null,
  changed_at timestamptz not null default now()
);
revoke all on private.support_status_log from public, anon, authenticated;

-- Owner sets or replaces the key in the Supabase SQL editor:
--   select private.set_support_ops_key('<the same long random value saved in Cloudflare>');
create or replace function private.set_support_ops_key(p_key text)
returns void language plpgsql security definer set search_path to '' as $f$
begin
  if char_length(coalesce(p_key, '')) < 32 then raise exception 'Use a random key of at least 32 characters'; end if;
  insert into private.support_ops_key(id, key_sha256)
    values (1, encode(extensions.digest(p_key, 'sha256'), 'hex'))
    on conflict (id) do update set key_sha256 = excluded.key_sha256, set_at = now();
end $f$;
revoke all on function private.set_support_ops_key(text) from public, anon, authenticated;

create or replace function public.ops_set_support_status(
  p_key text, p_channel text, p_id uuid, p_status text, p_outcome text, p_note text, p_by text)
returns jsonb language plpgsql security definer set search_path to '' as $f$
declare want text; old_status text; found boolean := false;
begin
  select key_sha256 into want from private.support_ops_key where id = 1;
  if want is null or encode(extensions.digest(coalesce(p_key, ''), 'sha256'), 'hex') <> want then
    perform pg_catalog.pg_sleep(0.5);
    raise exception 'not allowed' using errcode = '42501';
  end if;
  if p_channel not in ('app','website') or p_status not in ('new','in_progress','answered','closed')
     or (p_outcome is not null and p_outcome not in ('solved','not_a_bug','feature_request','duplicate','no_reply','other'))
     or char_length(coalesce(p_note, '')) > 1000 or char_length(coalesce(p_by, '')) not between 3 and 200 then
    raise exception 'invalid request' using errcode = '22023';
  end if;
  if p_status = 'closed' and p_outcome is null then
    raise exception 'closing a ticket needs an outcome' using errcode = '22023';
  end if;
  if p_channel = 'app' then
    select status into old_status from public.support_requests where id = p_id for update;
    found := found or old_status is not null;
    update public.support_requests set status = p_status, outcome = p_outcome,
      resolution_note = nullif(btrim(coalesce(p_note, '')), ''), status_changed_at = now(), status_changed_by = p_by
      where id = p_id;
  else
    select status into old_status from public.public_support_requests where id = p_id for update;
    found := found or old_status is not null;
    update public.public_support_requests set status = p_status, outcome = p_outcome,
      resolution_note = nullif(btrim(coalesce(p_note, '')), ''), status_changed_at = now(), status_changed_by = p_by
      where id = p_id;
  end if;
  if not found then raise exception 'ticket not found' using errcode = 'P0002'; end if;
  insert into private.support_status_log(channel, request_id, old_status, new_status, outcome, changed_by)
    values (p_channel, p_id, old_status, p_status, p_outcome, p_by);
  return jsonb_build_object('status', p_status, 'outcome', p_outcome, 'changed_at', now());
end $f$;
revoke all on function public.ops_set_support_status(text, text, uuid, text, text, text, text) from public, authenticated;
grant execute on function public.ops_set_support_status(text, text, uuid, text, text, text, text) to anon;
