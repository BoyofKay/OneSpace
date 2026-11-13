-- Profiles use column-scoped grants; prior migrations added columns but
-- missed the matching UPDATE grants. Owner-only RLS still restricts writes.
grant update (
 time_zone,city_weather_shared,city_name,temperature_c,weather_code,
 weather_updated_at,weather_city_id,weather_city_lat,weather_city_lon,
 weather_high_c,weather_low_c,weather_rain_pct
) on public.profiles to authenticated;
