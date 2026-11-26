-- 0324 (26 Nov 2026, UAT): notification texts follow the person's app language.
-- private.compose_notification_text already writes push_title/push_body in the
-- recipient's language, but only when a notification is created or changed, so
-- notifications made before someone switched to Arabic stayed in English.
-- When profiles.locale changes, that person's notifications from the last 90 days
-- are re-composed in the new language. Touching headline does not send any push
-- again (pushes are queued only on insert, created_at or read_at).
-- QA first; Production at the next go-live.

create or replace function private.recompose_notifications_on_locale()
returns trigger language plpgsql security definer set search_path to '' as $f$
begin
  if new.locale is distinct from old.locale then
    update public.space_notifications n set headline = n.headline
      where n.recipient_id = new.id and n.created_at > now() - interval '90 days';
  end if;
  return null;
end $f$;
revoke all on function private.recompose_notifications_on_locale() from public, anon, authenticated;

drop trigger if exists recompose_notifications_on_locale on public.profiles;
create trigger recompose_notifications_on_locale after update of locale on public.profiles
  for each row execute function private.recompose_notifications_on_locale();
