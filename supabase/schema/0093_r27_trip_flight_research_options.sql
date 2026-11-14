-- R27: Trip research board for candidate airfares and route comparisons.
-- Candidate prices/availability are entered by the user and may become stale.
-- A booking only becomes an itinerary item through an explicit user action.
create table public.trip_flight_options(
 id uuid primary key default gen_random_uuid(),
 trip_id uuid not null references public.shared_trips(id) on delete cascade,
 created_by uuid not null default auth.uid() references auth.users(id),
 title text not null check(length(btrim(title)) between 1 and 160),
 provider text not null default '' check(length(provider)<=140),
 airline text not null default '' check(length(airline)<=140),
 origin text not null default '' check(length(origin)<=180),
 destination text not null default '' check(length(destination)<=180),
 departure_on date,
 return_on date,
 flexible_dates boolean not null default false,
 stops integer check(stops between 0 and 8),
 baggage_details text not null default '' check(length(baggage_details)<=800),
 price numeric(12,2) check(price between 0 and 999999999.99),
 currency text not null default 'USD' check(currency ~ '^[A-Z]{3}$'),
 preference_score integer check(preference_score between 1 and 5),
 booking_link text not null default '' check(length(booking_link)<=1800 and
  (booking_link='' or booking_link ~* '^https?://[^[:space:]/]+')),
 status text not null default 'considering'
  check(status in ('considering','proposed','booked','rejected')),
 notes text not null default '' check(length(notes)<=2200),
 archived_at timestamptz,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 check(return_on is null or departure_on is null or return_on>=departure_on)
);
create index trip_flight_options_trip on public.trip_flight_options(trip_id,updated_at desc);
alter table public.trip_flight_options enable row level security;
create policy "Read options of visible trips" on public.trip_flight_options
 for select to authenticated using(exists(
 select 1 from public.shared_trips t where t.id=trip_id));
create policy "Add option to editable trip" on public.trip_flight_options
 for insert to authenticated with check(
 created_by=(select auth.uid()) and exists(
 select 1 from public.shared_trips t where t.id=trip_id and
 (t.visibility='shared' or t.created_by=(select auth.uid()))));
create policy "Edit option under editable trip" on public.trip_flight_options
 for update to authenticated using(exists(
 select 1 from public.shared_trips t where t.id=trip_id and
 (t.visibility='shared' or t.created_by=(select auth.uid()))))
 with check(exists(select 1 from public.shared_trips t where t.id=trip_id
 and (t.visibility='shared' or t.created_by=(select auth.uid()))));
revoke all on public.trip_flight_options from public,anon,authenticated;
grant select on public.trip_flight_options to authenticated;
grant insert(trip_id,title,provider,airline,origin,destination,departure_on,
 return_on,flexible_dates,stops,baggage_details,price,currency,
 preference_score,booking_link,status,notes) on public.trip_flight_options
 to authenticated;
grant update(title,provider,airline,origin,destination,departure_on,
 return_on,flexible_dates,stops,baggage_details,price,currency,
 preference_score,booking_link,status,notes,archived_at)
 on public.trip_flight_options to authenticated;

create function private.trip_flight_option_timestamps()
returns trigger language plpgsql set search_path='' as $$
begin
 if tg_op='UPDATE' and new.trip_id<>old.trip_id then
 raise exception 'Cannot move a candidate to another trip';end if;
 new.updated_at=now();return new;
end $$;
create trigger trip_flight_timestamp before update on public.trip_flight_options
 for each row execute function private.trip_flight_option_timestamps();
revoke all on function private.trip_flight_option_timestamps()
 from public,anon,authenticated;
alter publication supabase_realtime add table public.trip_flight_options;
