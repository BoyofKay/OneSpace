-- R59 (Ahmed, 15 Nov): "Download my data" and "Delete my account".
-- Decision D47: shared items stay for the partner; private items, profile,
-- devices and personal settings are removed after a 7-day grace period.
-- The sign-in itself is soft-deleted by the onespace-account-purge Edge
-- Function (auth.admin.deleteUser(id, true)), so shared rows keep a valid
-- author while the email/phone are anonymised.

create table if not exists public.account_deletion_requests (
  user_id uuid primary key references auth.users(id) on delete cascade,
  requested_at timestamptz not null default now(),
  purge_after timestamptz not null default now() + interval '7 days',
  cancelled_at timestamptz,
  completed_at timestamptz,
  last_error text check (last_error is null or char_length(last_error) <= 2000)
);
alter table public.account_deletion_requests enable row level security;
drop policy if exists "Read my deletion request" on public.account_deletion_requests;
create policy "Read my deletion request" on public.account_deletion_requests
  for select to authenticated using (user_id = (select auth.uid()));
revoke insert, update, delete on public.account_deletion_requests from authenticated, anon;
grant select on public.account_deletion_requests to authenticated;

create or replace function public.request_account_deletion()
returns timestamptz language plpgsql security definer set search_path to '' as $$
declare me uuid := auth.uid(); due timestamptz;
begin
  if me is null then raise exception 'Sign in first'; end if;
  insert into public.account_deletion_requests(user_id, requested_at, purge_after)
  values (me, now(), now() + interval '7 days')
  on conflict (user_id) do update set requested_at = now(),
    purge_after = now() + interval '7 days', cancelled_at = null,
    completed_at = null, last_error = null
  returning purge_after into due;
  return due;
end $$;

create or replace function public.cancel_account_deletion()
returns void language plpgsql security definer set search_path to '' as $$
begin
  update public.account_deletion_requests set cancelled_at = now()
   where user_id = auth.uid() and completed_at is null;
end $$;

-- Every row the signed-in person wrote or received, plus their profile.
create or replace function public.export_my_data()
returns jsonb language plpgsql security definer set search_path to '' stable as $$
declare
  me uuid := auth.uid();
  result jsonb;
  t record;
  rows jsonb;
begin
  if me is null then raise exception 'Sign in first'; end if;
  result := jsonb_build_object(
    'exported_at', now(),
    'format', 'OneSpace export v1',
    'note', 'Everything you created or received in OneSpace. Shared items your partner created are not included.',
    'profile', (select to_jsonb(p) from public.profiles p where p.id = me));
  for t in
    select c.table_name,
      string_agg(format('%I = $1', c.column_name), ' or ') as cond
    from information_schema.columns c
    join information_schema.tables x on x.table_schema = c.table_schema
      and x.table_name = c.table_name and x.table_type = 'BASE TABLE'
    where c.table_schema = 'public'
      and c.column_name in ('created_by','user_id','sender_id','owner_id','author_id','recipient_id')
      and c.table_name not in ('account_deletion_requests')
    group by c.table_name order by c.table_name
  loop
    execute format('select coalesce(jsonb_agg(to_jsonb(r)), ''[]''::jsonb) from public.%I r where %s',
      t.table_name, t.cond) into rows using me;
    if t.table_name = 'push_devices' then
      rows := (select coalesce(jsonb_agg(e - 'token' - 'fcm_token'), '[]'::jsonb) from jsonb_array_elements(rows) e);
    end if;
    if jsonb_array_length(rows) > 0 then
      result := result || jsonb_build_object(t.table_name, rows);
    end if;
  end loop;
  return result;
end $$;

-- Removes private and personal data; returns the storage files to delete.
create or replace function private.purge_account_data(target uuid)
returns jsonb language plpgsql security definer set search_path to '' as $$
declare
  files jsonb := '[]'::jsonb;
  t record;
begin
  -- Files that belong to private items.
  files := files || coalesce((select jsonb_agg(jsonb_build_object('bucket','onespace-memory-photos','path',mp.object_path))
    from public.memory_photos mp join public.memories m on m.id = mp.memory_id
    where m.created_by = target and m.visibility = 'private'), '[]');
  files := files || coalesce((select jsonb_agg(jsonb_build_object('bucket','onespace-note-images','path',ni.object_path))
    from public.note_images ni join public.notes n on n.id = ni.note_id
    where n.created_by = target and n.visibility = 'private'), '[]');
  files := files || coalesce((select jsonb_agg(jsonb_build_object('bucket','onespace-trip-documents','path',ta.object_path))
    from public.trip_attachments ta join public.shared_trips s on s.id = ta.trip_id
    where s.created_by = target and s.visibility = 'private'), '[]');
  files := files || coalesce((select jsonb_agg(jsonb_build_object('bucket','onespace-share-in','path',i.file_path))
    from public.items_to_sort i
    where i.created_by = target and i.visibility = 'private' and i.file_path is not null), '[]');
  files := files || coalesce((select jsonb_agg(jsonb_build_object('bucket','onespace-activity-voice','path',ac.voice_path))
    from public.activity_comments ac join public.activities a on a.id = ac.activity_id
    where a.created_by = target and a.visibility = 'private' and ac.voice_path is not null), '[]');

  -- Private items (their child rows follow by cascade).
  for t in
    select c.table_name from information_schema.columns c
    join information_schema.columns v on v.table_schema = c.table_schema
      and v.table_name = c.table_name and v.column_name = 'visibility'
    join information_schema.tables x on x.table_schema = c.table_schema
      and x.table_name = c.table_name and x.table_type = 'BASE TABLE'
    where c.table_schema = 'public' and c.column_name = 'created_by'
  loop
    execute format('delete from public.%I where created_by = $1 and visibility = ''private''', t.table_name)
      using target;
  end loop;

  -- Personal settings and devices.
  delete from public.push_devices where user_id = target;
  delete from public.personal_days_off where user_id = target;
  delete from public.user_attention_snoozes where user_id = target;
  delete from public.activity_attention_snoozes where user_id = target;
  delete from public.gesture_message_overrides where owner_id = target;
  delete from public.space_notifications where recipient_id = target;

  -- The profile stays only as "Former partner" so shared items keep an author.
  update public.profiles set display_name = 'Former partner', city_name = null,
    city_weather_shared = false, temperature_c = null, weather_code = null,
    weather_updated_at = null, weather_city_id = null, weather_city_lat = null,
    weather_city_lon = null, weather_high_c = null, weather_low_c = null,
    weather_rain_pct = null, partner_label = null, partner_labels = '{}',
    time_zone = null, receive_automatic_gestures = false
  where id = target;

  -- Leaves the shared space; the partner keeps it and everything shared.
  delete from public.space_members where user_id = target;

  return files;
end $$;
revoke all on function private.purge_account_data(uuid) from public, anon, authenticated;

-- Called only by the purge Edge Function (service role).
create or replace function public.purge_due_accounts_list()
returns setof uuid language sql security definer set search_path to '' as $$
  select user_id from public.account_deletion_requests
  where cancelled_at is null and completed_at is null and purge_after <= now()
  order by purge_after limit 20;
$$;
create or replace function public.purge_account_data_service(target uuid)
returns jsonb language plpgsql security definer set search_path to '' as $$
begin
  if not exists (select 1 from public.account_deletion_requests
     where user_id = target and cancelled_at is null and completed_at is null and purge_after <= now()) then
    raise exception 'No due deletion request for this account';
  end if;
  return private.purge_account_data(target);
end $$;
create or replace function public.finish_account_purge(target uuid, failure text default null)
returns void language sql security definer set search_path to '' as $$
  update public.account_deletion_requests
     set completed_at = case when failure is null then now() else null end,
         last_error = failure
   where user_id = target;
$$;
revoke all on function public.purge_due_accounts_list() from public, anon, authenticated;
revoke all on function public.purge_account_data_service(uuid) from public, anon, authenticated;
revoke all on function public.finish_account_purge(uuid, text) from public, anon, authenticated;
grant execute on function public.purge_due_accounts_list() to service_role;
grant execute on function public.purge_account_data_service(uuid) to service_role;
grant execute on function public.finish_account_purge(uuid, text) to service_role;
revoke all on function public.request_account_deletion() from public, anon;
revoke all on function public.cancel_account_deletion() from public, anon;
revoke all on function public.export_my_data() from public, anon;
grant execute on function public.request_account_deletion() to authenticated;
grant execute on function public.cancel_account_deletion() to authenticated;
grant execute on function public.export_my_data() to authenticated;

-- Daily run (03:17 UTC) of the purge worker.
select cron.unschedule('onespace-account-purge') where exists (select 1 from cron.job where jobname = 'onespace-account-purge');
select cron.schedule('onespace-account-purge', '17 3 * * *', $c$
  select net.http_post(
    url := 'https://ugwrpeduzyzrujkizqfo.supabase.co/functions/v1/onespace-account-purge',
    headers := jsonb_build_object('Content-Type','application/json',
      'x-onespace-push-secret',
      (select decrypted_secret from vault.decrypted_secrets where name='onespace_push_worker_secret' limit 1)),
    body := '{}'::jsonb, timeout_milliseconds := 60000);
$c$);
