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
