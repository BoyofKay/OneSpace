-- Coordinate: reusable person/business contact information.
-- No existing Activities or components are modified or deleted.
-- Structured values live within the existing RLS-protected component payload.
ALTER TABLE public.activity_components
  DROP CONSTRAINT activity_components_kind_check;
ALTER TABLE public.activity_components
  ADD CONSTRAINT activity_components_kind_check
  CHECK (kind IN (
    'link','note','option','step','date','price','spec',
    'reminder','tag','mention','location','image','contact'
  ));
