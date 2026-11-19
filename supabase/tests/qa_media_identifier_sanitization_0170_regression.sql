-- QA media-free structured sanitizer regression. Pure JSON fixture, no writes.
do $qa$
declare
  source jsonb;
  clean jsonb;
begin
  source:=jsonb_build_object(
    'title','Our scrapbook weekend',
    'story_text','We shared a lovely weekend',
    'photo_1_id','11a254bb-8811-4000-8000-000000000001',
    'photo_4_id','11a254bb-8811-4000-8000-000000000004',
    'image_3_id','11a254bb-8811-4000-8000-000000000003',
    'file_name','sensitive-passport.pdf','file_mime','application/pdf',
    'file_size',12345,'voice_seconds',39,
    'photo_caption','We watched the sunrise together',
    'source_url','https://example.org/our-article',
    'nested',jsonb_build_object(
      'cover_photo_id','11a254bb-8811-4000-8000-000000000002',
      'document_id','11a254bb-8811-4000-8000-000000000005',
      'notes','Keep this ordinary note',
      'description','Written memory and https://files.example.org/storage/v1/object/public/photos/a.jpg'),
    'quill',jsonb_build_array(jsonb_build_object('insert',
      jsonb_build_object('image','data:image/png;base64,QUJD')),
      jsonb_build_object('insert','Our handwritten memory')));
  clean:=private.qa_structured_value(source);
  if clean ?| array['photo_1_id','photo_4_id','image_3_id','file_name',
                    'file_mime','file_size','voice_seconds']
     or clean#>'{nested}' ?| array['cover_photo_id','document_id']
     or clean::text like '%sensitive-passport.pdf%'
     or clean::text like '%storage/v1/object%'
     or clean::text like '%base64%'
     or clean::text like '%11a254bb%'
  then raise exception 'Indirect media pointer or bytes leaked: %',clean; end if;
  if clean->>'title'<>'Our scrapbook weekend'
    or clean->>'story_text'<>'We shared a lovely weekend'
    or clean->>'photo_caption'<>'We watched the sunrise together'
    or clean->>'source_url'<>'https://example.org/our-article'
    or clean#>>'{nested,notes}'<>'Keep this ordinary note'
    or clean::text not like '%Our handwritten memory%'
    or clean::text not like '%Written memory%'
    or clean::text not like '%[uploaded media excluded]%'
  then raise exception 'Sanitizer erased ordinary structured/written data: %',clean;
  end if;
end $qa$;
select 'PASS: indirect photo/document identifiers and file metadata excluded, prose and external article link preserved' result;
