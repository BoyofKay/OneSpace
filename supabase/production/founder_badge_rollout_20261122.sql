-- Production rollout of QA 0318 and subsequent 0319 hardening.
-- Prerequisites verified against Production: existing private.founder_members,
-- private.founder_couples and auth.users. No users or website Founder rows modified.
-- Apply this as one tracked Supabase migration only after QA 0319 passes.

-- QA 0318 (Amr, 22 Nov 2026): Founding 500 in the app.
-- * The first 500 PEOPLE (website and app share one list, matched by email) are Founder Members.
-- * Website founders (private.founder_members, confirmed, in a 'founder' couple) are Founders in the app.
-- * After that, people who sign up in the app while fewer than 500 Founders exist get the offer:
--   the sign-up trigger sets user_metadata.founder = true, the "Confirm your email" template says
--   "You're one of the Founding 500", and the badge is granted when the email is confirmed.
-- * No Founder number is ever stored for the app, shown or emailed. granted_at is the real order.
-- * Accounts that already existed before this migration are not backfilled (testers).

create table if not exists private.app_founders (
  user_id uuid primary key references auth.users(id) on delete cascade,
  email_norm text not null,
  source text not null check (source in ('website', 'app')),
  granted_at timestamptz not null default now()
);
revoke all on private.app_founders from public, anon, authenticated;
alter table private.app_founders enable row level security;  -- no policies: only definer functions read it

create or replace function private.is_website_founder(p_email text)
returns boolean language sql stable security definer set search_path to '' as $function$
  select exists (
    select 1 from private.founder_members m
    join private.founder_couples c on c.id = m.couple_id
    where m.email_norm = lower(btrim(coalesce(p_email, '')))
      and m.confirmed_at is not null and c.status = 'founder');
$function$;

-- People who are Founders so far: confirmed website Founders plus app-only Founders.
create or replace function private.founder_people_count()
returns int language sql stable security definer set search_path to '' as $function$
  select ((select count(*) from private.founder_members m
           join private.founder_couples c on c.id = m.couple_id
           where m.confirmed_at is not null and c.status = 'founder')
        + (select count(*) from private.app_founders a
           where a.source = 'app' and not private.is_website_founder(a.email_norm)))::int;
$function$;

-- Before the account row is written: mark the Founder offer in user_metadata so the
-- confirmation email can acknowledge it. Never blocks a sign-up.
create or replace function private.founder_offer_on_signup()
returns trigger language plpgsql security definer set search_path to '' as $function$
begin
  begin
    if new.email is not null
       and (private.is_website_founder(new.email) or private.founder_people_count() < 500) then
      new.raw_user_meta_data := coalesce(new.raw_user_meta_data, '{}'::jsonb) || jsonb_build_object('founder', true);
    end if;
  exception when others then
    null;  -- the badge is a thank-you, never a reason for a failed sign-up
  end;
  return new;
end $function$;

-- When the email is confirmed (or an account is created already confirmed): grant the badge.
create or replace function private.founder_grant_on_confirm()
returns trigger language plpgsql security definer set search_path to '' as $function$
begin
  if new.email_confirmed_at is not null
     and (tg_op = 'INSERT' or old.email_confirmed_at is null) then
    begin
      if private.is_website_founder(new.email) then
        insert into private.app_founders(user_id, email_norm, source)
          values (new.id, lower(btrim(new.email)), 'website') on conflict (user_id) do nothing;
      elsif coalesce((new.raw_user_meta_data ->> 'founder')::boolean, false) then
        insert into private.app_founders(user_id, email_norm, source)
          values (new.id, lower(btrim(new.email)), 'app') on conflict (user_id) do nothing;
      end if;
    exception when others then
      null;
    end;
  end if;
  return new;
end $function$;

drop trigger if exists onespace_founder_offer on auth.users;
create trigger onespace_founder_offer before insert on auth.users
  for each row execute function private.founder_offer_on_signup();
drop trigger if exists onespace_founder_grant on auth.users;
create trigger onespace_founder_grant after insert or update of email_confirmed_at on auth.users
  for each row execute function private.founder_grant_on_confirm();

-- The app asks once per Me screen. Also picks up a website confirmation that happened after
-- the app account was created (same email).
create or replace function public.my_founder_status()
returns boolean language plpgsql security definer set search_path to '' as $function$
declare
  me uuid := auth.uid();
  my_email text;
begin
  if me is null then return false; end if;
  if exists (select 1 from private.app_founders where user_id = me) then return true; end if;
  select u.email into my_email from auth.users u where u.id = me;
  if my_email is not null and private.is_website_founder(my_email) then
    insert into private.app_founders(user_id, email_norm, source)
      values (me, lower(btrim(my_email)), 'website') on conflict (user_id) do nothing;
    return true;
  end if;
  return false;
end $function$;

revoke all on function private.is_website_founder(text) from public, anon, authenticated;
revoke all on function private.founder_people_count() from public, anon, authenticated;
revoke all on function private.founder_offer_on_signup() from public, anon, authenticated;
revoke all on function private.founder_grant_on_confirm() from public, anon, authenticated;
revoke all on function public.my_founder_status() from public, anon;
grant execute on function public.my_founder_status() to authenticated;


-- 0319: Server-authoritative Founder Member offers and quota (QA, then Production).
-- Preserve public sign-up email template's .Data.founder flag, but never use
-- raw_user_meta_data to authorize Founder membership (it is user-editable).
-- Reserve app offers in server-only raw_app_meta_data; count pending offers
-- so multiple unconfirmed signups cannot all claim the last Founder places.
-- Existing confirmed website Founders remain eligible, including older accounts.

create or replace function private.founder_people_count()
returns int language sql volatile security definer set search_path to '' as $function$
  select (
    (select count(*) from private.founder_members m
       join private.founder_couples c on c.id=m.couple_id
       where m.confirmed_at is not null and c.status='founder')
    + (select count(*) from private.app_founders a
       where a.source='app' and not private.is_website_founder(a.email_norm))
    + (select count(*) from auth.users u
       where u.email_confirmed_at is null
         and (u.raw_app_meta_data ->> 'onespace_founder_offer') = 'true'
         and not private.is_website_founder(u.email))
  )::int;
$function$;

create or replace function private.founder_offer_on_signup()
returns trigger language plpgsql security definer set search_path to '' as $function$
begin
  -- A client may send user_metadata.founder=true in its signup payload.
  -- Clear client assertions and set the email-template hint from the server.
  new.raw_user_meta_data := coalesce(new.raw_user_meta_data, '{}'::jsonb) - 'founder';
  new.raw_app_meta_data := coalesce(new.raw_app_meta_data, '{}'::jsonb) - 'onespace_founder_offer';
  begin
    -- All app signup allocations serialize on this lock.
    perform pg_catalog.pg_advisory_xact_lock(1500500);
    if new.email is not null and (
         private.is_website_founder(new.email)
         or private.founder_people_count() < 500) then
      new.raw_user_meta_data := new.raw_user_meta_data || jsonb_build_object('founder', true);
      new.raw_app_meta_data := new.raw_app_meta_data || jsonb_build_object('onespace_founder_offer', true);
    end if;
  exception when others then
    null;  -- A badge error must never prevent ordinary account registration.
  end;
  return new;
end $function$;

create or replace function private.founder_grant_on_confirm()
returns trigger language plpgsql security definer set search_path to '' as $function$
begin
  if new.email_confirmed_at is not null
     and (tg_op = 'INSERT' or old.email_confirmed_at is null) then
    begin
      if private.is_website_founder(new.email) then
        insert into private.app_founders(user_id, email_norm, source)
          values (new.id, lower(btrim(new.email)), 'website')
          on conflict (user_id) do nothing;
      elsif coalesce((new.raw_app_meta_data ->> 'onespace_founder_offer')::boolean, false) then
        insert into private.app_founders(user_id, email_norm, source)
          values (new.id, lower(btrim(new.email)), 'app')
          on conflict (user_id) do nothing;
      end if;
    exception when others then
      null;  -- Preserve signup/confirmation even if the optional badge fails.
    end;
  end if;
  return new;
end $function$;

revoke all on function private.founder_people_count() from public, anon, authenticated;
revoke all on function private.founder_offer_on_signup() from public, anon, authenticated;
revoke all on function private.founder_grant_on_confirm() from public, anon, authenticated;
