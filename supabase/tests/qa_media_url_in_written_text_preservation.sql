begin;
do $test$
declare v jsonb;
begin
  v:=private.qa_structured_value(
    '{"body":"Beginning of my note https://example.org/storage/v1/object/public/photos/abc.png and the ending",
       "rich_delta":[{"insert":"Hello data:image/png;base64,AAAA World"},{"insert":{"image":"img.png"}}],
       "payload":{"caption":"My saved description","file_path":"/storage/v1/object/private/pdf.pdf"}}'::jsonb);
  if v->>'body' not like 'Beginning of my note % and the ending'
    or v->>'body' like '%storage/v1/object%'
    or v::text like '%data:image%'
    or v::text like '%file_path%'
    or v::text like '%"image"%' then
    raise exception 'Media-stripping swallowed words or leaked media: %',v;
  end if;
  if v #>> '{payload,caption}'<>'My saved description' then
    raise exception 'A structured caption was wrongly removed';
  end if;
end $test$;
rollback;
select 'PASS: media URL removed without losing surrounding text; embedded data URI removed; structured caption preserved' result;
