-- Initialize each person's language from validated sign-up metadata.
-- No authorization or RLS decisions depend on this user-editable field.
create or replace function private.handle_new_user()
returns trigger
language plpgsql security definer
set search_path = ''
as $$
begin
  insert into public.profiles(id, display_name, locale)
  values (
    new.id,
    coalesce(nullif(left(btrim(new.raw_user_meta_data ->> 'display_name'), 80), ''), 'Someone'),
    case
      when new.raw_user_meta_data ->> 'locale' = 'ar' then 'ar'
      else 'en'
    end
  )
  on conflict (id) do nothing;
  return new;
end;
$$;
