-- R64: Help & support — contact us, report a technical issue, suggest an idea.
-- Each person can send and read only their own requests. Ahmed reads all of
-- them in the Supabase dashboard (Table editor → support_requests).
create table if not exists public.support_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  kind text not null check (kind in ('contact','issue','idea')),
  subject text not null check (char_length(btrim(subject)) between 1 and 160),
  message text not null check (char_length(btrim(message)) between 1 and 4000),
  reply_email text check (reply_email is null or (char_length(reply_email) <= 254 and reply_email ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$')),
  app_version text check (char_length(app_version) <= 40),
  platform text check (platform in ('android','ios','other')),
  locale text check (locale in ('en','ar')),
  diagnostics text check (char_length(diagnostics) <= 8000),
  status text not null default 'new' check (status in ('new','in_progress','answered','closed')),
  created_at timestamptz not null default now()
);
create index if not exists support_requests_user_idx on public.support_requests (user_id, created_at desc);
alter table public.support_requests enable row level security;

drop policy if exists support_requests_insert_own on public.support_requests;
create policy support_requests_insert_own on public.support_requests
  for insert to authenticated with check (user_id = (select auth.uid()) and status = 'new');
drop policy if exists support_requests_select_own on public.support_requests;
create policy support_requests_select_own on public.support_requests
  for select to authenticated using (user_id = (select auth.uid()));

revoke all on public.support_requests from anon;
grant select, insert on public.support_requests to authenticated;

-- Gentle limit: at most 10 requests per person per day.
create or replace function private.support_request_rate_limit()
returns trigger language plpgsql security definer set search_path to '' as $$
begin
  if (select count(*) from public.support_requests
       where user_id = new.user_id and created_at > now() - interval '1 day') >= 10 then
    raise exception 'You have sent several messages today. Please try again tomorrow.';
  end if;
  return new;
end $$;
drop trigger if exists support_requests_rate_limit on public.support_requests;
create trigger support_requests_rate_limit before insert on public.support_requests
  for each row execute function private.support_request_rate_limit();
