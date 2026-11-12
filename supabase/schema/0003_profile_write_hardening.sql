-- Let the database own profile audit timestamps.
create or replace function private.touch_profile_updated_at()
returns trigger language plpgsql set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create trigger profile_updated_at
before update on public.profiles
for each row execute function private.touch_profile_updated_at();

-- Profiles are automatically created by the auth-user trigger.
-- Clients can edit only their display name and language preference.
revoke insert, update on public.profiles from authenticated;
grant update (display_name, locale) on public.profiles to authenticated;
