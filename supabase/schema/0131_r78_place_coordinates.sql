-- R78: places can be shown on a map; a link shared from Google/Apple Maps is kept.
-- Applied 16 Nov 2026. (places has table-level grants, so no column grants needed.)
alter table public.places
  add column if not exists latitude double precision check (latitude between -90 and 90),
  add column if not exists longitude double precision check (longitude between -180 and 180),
  add column if not exists map_url text not null default '' check (char_length(map_url) <= 1000);
alter table public.places add constraint places_coordinates_pair
  check ((latitude is null) = (longitude is null));
