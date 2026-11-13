-- Optional private images for Coordinate Activities.
-- Only partner-authorized objects may be signed; uploads belong to the
-- authenticated contributor and must use activity/user/random filenames.
INSERT INTO storage.buckets (
  id, name, public, file_size_limit, allowed_mime_types
) VALUES (
  'onespace-activity-media','onespace-activity-media',false,6291456,
  ARRAY['image/jpeg','image/png','image/webp']::text[]
) ON CONFLICT (id) DO NOTHING;

ALTER TABLE public.activity_components
  DROP CONSTRAINT activity_components_kind_check;
ALTER TABLE public.activity_components
  ADD CONSTRAINT activity_components_kind_check
  CHECK (kind IN (
    'link','note','option','step','date','price','spec',
    'reminder','tag','mention','location','image'
  ));

CREATE POLICY "OneSpace readable Activity media"
ON storage.objects FOR SELECT TO authenticated
USING (
  bucket_id='onespace-activity-media'
  AND array_length(storage.foldername(name),1)=2
  AND EXISTS (
    SELECT 1 FROM public.activities a
    WHERE a.id::text=(storage.foldername(name))[1]
  )
);

CREATE POLICY "OneSpace contributor media uploads"
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (
  bucket_id='onespace-activity-media'
  AND array_length(storage.foldername(name),1)=2
  AND (storage.foldername(name))[2]=(SELECT auth.uid())::text
  AND storage.extension(name) IN ('jpg','jpeg','png','webp')
  AND EXISTS (
    SELECT 1 FROM public.activities a
    WHERE a.id::text=(storage.foldername(name))[1]
      AND (a.visibility='shared' OR a.created_by=(SELECT auth.uid()))
  )
);

-- Allow failed uploads to be cleaned up by their contributor, but never
-- permit deletion after the media has been attached to a shared Activity.
CREATE POLICY "OneSpace cleanup unused own Activity media"
ON storage.objects FOR DELETE TO authenticated
USING (
  bucket_id='onespace-activity-media'
  AND (storage.foldername(name))[2]=(SELECT auth.uid())::text
  AND EXISTS (
    SELECT 1 FROM public.activities a
    WHERE a.id::text=(storage.foldername(name))[1]
      AND (a.visibility='shared' OR a.created_by=(SELECT auth.uid()))
  )
  AND NOT EXISTS (
    SELECT 1 FROM public.activity_components c
    WHERE c.activity_id::text=(storage.foldername(name))[1]
      AND c.payload->>'object_path'=storage.objects.name
  )
);
