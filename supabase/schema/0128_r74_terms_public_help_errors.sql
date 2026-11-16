-- R74: terms acceptance, help without signing in, automatic error reports.
-- Applied 16 Nov 2026 (tested in rolled-back blocks: anon can submit but not
-- read; 3 messages per email per hour; error log insert-only).
alter table public.profiles add column if not exists terms_accepted_at timestamptz,
  add column if not exists terms_version text check (char_length(terms_version) <= 20);

create or replace function public.accept_terms(p_version text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise exception 'Sign in required'; end if;
  if coalesce(p_version,'') !~ '^[0-9a-z.\-]{1,20}$' then raise exception 'Invalid terms version'; end if;
  update public.profiles set terms_accepted_at = now(), terms_version = p_version where id = auth.uid();
end $$;
revoke all on function public.accept_terms(text) from public, anon;
grant execute on function public.accept_terms(text) to authenticated;

-- Messages from people who cannot sign in. Nobody can read them through the API.
create table if not exists public.public_support_requests (
  id uuid primary key default gen_random_uuid(),
  kind text not null check (kind in ('contact','issue','account')),
  subject text not null check (char_length(btrim(subject)) between 1 and 160),
  message text not null check (char_length(btrim(message)) between 1 and 4000),
  reply_email text not null check (char_length(reply_email) <= 254 and reply_email ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  app_version text check (char_length(app_version) <= 40),
  platform text check (platform in ('android','ios','other')),
  locale text check (locale in ('en','ar')),
  diagnostics text check (char_length(diagnostics) <= 4000),
  status text not null default 'new' check (status in ('new','in_progress','answered','closed')),
  created_at timestamptz not null default now()
);
alter table public.public_support_requests enable row level security;
revoke all on public.public_support_requests from anon, authenticated;

create or replace function public.submit_public_support(p_kind text, p_subject text, p_message text,
  p_reply_email text, p_app_version text, p_platform text, p_locale text, p_diagnostics text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if (select count(*) from public.public_support_requests where created_at > now() - interval '1 hour') >= 30
     or (select count(*) from public.public_support_requests
         where lower(reply_email) = lower(btrim(p_reply_email)) and created_at > now() - interval '1 hour') >= 3 then
    raise exception 'Too many messages. Please try again later.';
  end if;
  insert into public.public_support_requests(kind, subject, message, reply_email, app_version, platform, locale, diagnostics)
  values (p_kind, btrim(p_subject), btrim(p_message), btrim(p_reply_email), left(p_app_version,40), p_platform, p_locale, left(p_diagnostics,4000));
end $$;
revoke all on function public.submit_public_support(text,text,text,text,text,text,text,text) from public;
grant execute on function public.submit_public_support(text,text,text,text,text,text,text,text) to anon, authenticated;

-- Crashes and errors reported by the app itself (no content, capped volume).
create table if not exists public.client_errors (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete set null,
  error text not null check (char_length(error) <= 1000),
  stack text check (char_length(stack) <= 4000),
  context text check (char_length(context) <= 300),
  app_version text check (char_length(app_version) <= 40),
  platform text check (char_length(platform) <= 20),
  created_at timestamptz not null default now()
);
create index if not exists client_errors_created_idx on public.client_errors(created_at desc);
alter table public.client_errors enable row level security;
revoke all on public.client_errors from anon, authenticated;

create or replace function public.log_client_error(p_error text, p_stack text, p_context text, p_app_version text, p_platform text)
returns void language plpgsql security definer set search_path = '' as $$
declare me uuid := auth.uid();
begin
  if (me is not null and (select count(*) from public.client_errors where user_id = me and created_at > now() - interval '1 hour') >= 40)
     or (select count(*) from public.client_errors where created_at > now() - interval '1 hour') >= 500 then
    return; -- quietly drop floods
  end if;
  insert into public.client_errors(user_id, error, stack, context, app_version, platform)
  values (me, left(coalesce(p_error,'?'),1000), left(p_stack,4000), left(p_context,300), left(p_app_version,40), left(p_platform,20));
end $$;
revoke all on function public.log_client_error(text,text,text,text,text) from public;
grant execute on function public.log_client_error(text,text,text,text,text) to anon, authenticated;

select cron.schedule('onespace-client-errors-cleanup', '23 4 * * *',
  $c$delete from public.client_errors where created_at < now() - interval '60 days'$c$);
