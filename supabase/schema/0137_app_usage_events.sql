-- D78 (17 Nov 2026): privacy-light app usage events for the Command Center.
-- Only an event NAME (pattern kind or kind/Detail), an optional number (seconds) and a time.
-- Never titles, notes, messages, names, photos or anything typed. Deleted with the account (cascade)
-- and after 180 days. Readable only by the service role / read-only reporting role (RLS, no policies).
create table if not exists private.app_events (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null check (char_length(name) <= 80 and name ~ '^[a-z0-9_]+(/[A-Za-z0-9_.-]+)?$'),
  value integer check (value is null or value between 0 and 86400),
  at timestamptz not null,
  received_at timestamptz not null default now(),
  platform text not null default 'other' check (platform in ('android','ios','other')),
  app_version text check (char_length(app_version) <= 40)
);
create index if not exists app_events_at_idx on private.app_events (at);
create index if not exists app_events_user_at_idx on private.app_events (user_id, at);
alter table private.app_events enable row level security;

-- Batched insert from the app. Signed-in users only; at most 200 events per call and 3,000 per day per user.
-- Bad rows are skipped, never fail the app.
create or replace function public.log_app_events(p_events jsonb, p_platform text default 'other', p_app_version text default null)
returns integer language plpgsql security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  n integer := 0;
begin
  if me is null or p_events is null or jsonb_typeof(p_events) <> 'array' or jsonb_array_length(p_events) > 200 then
    return 0;
  end if;
  if (select count(*) from private.app_events where user_id = me and received_at > now() - interval '1 day') >= 3000 then
    return 0;
  end if;
  insert into private.app_events (user_id, name, value, at, platform, app_version)
  select me, e->>'n',
    case when (e->>'v') ~ '^[0-9]{1,5}$' then least((e->>'v')::int, 86400) end,
    case when (e->>'t') ~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})$'
      then greatest(least((e->>'t')::timestamptz, now() + interval '5 minutes'), now() - interval '7 days')
      else now() end,
    case when p_platform in ('android','ios') then p_platform else 'other' end,
    left(p_app_version, 40)
  from jsonb_array_elements(p_events) e
  where jsonb_typeof(e) = 'object'
    and char_length(coalesce(e->>'n','')) between 1 and 80
    and (e->>'n') ~ '^[a-z0-9_]+(/[A-Za-z0-9_.-]+)?$';
  get diagnostics n = row_count;
  return n;
exception when others then
  return 0;
end $$;
revoke all on function public.log_app_events(jsonb, text, text) from public, anon;
grant execute on function public.log_app_events(jsonb, text, text) to authenticated;

select cron.schedule('onespace-app-events-cleanup', '41 4 * * *',
  $c$delete from private.app_events where at < now() - interval '180 days'$c$);
