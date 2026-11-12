-- R2: real location component that can open an external map.
-- No location permission or background location tracking.
alter table public.activity_components drop constraint activity_components_kind_check;
alter table public.activity_components add constraint activity_components_kind_check
check (kind in ('link','note','option','step','date','price','spec','reminder','tag','mention','location'));
