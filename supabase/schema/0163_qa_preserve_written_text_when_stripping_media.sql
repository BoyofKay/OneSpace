-- QA-only media link redaction without losing adjacent written content.
create or replace function private.qa_structured_value(p_value jsonb)
returns jsonb language plpgsql immutable set search_path='' as $fn$
declare
  typ text;
  item record;
  result jsonb;
  sanitized jsonb;
  k text;
begin
  if p_value is null then return 'null'::jsonb; end if;
  typ:=jsonb_typeof(p_value);
  if typ='object' then
    result:='{}'::jsonb;
    for item in select key,value from jsonb_each(p_value) loop
      k:=lower(item.key);
      -- Exclude file/media bodies, file pointers and embedded Quill media.
      -- Ordinary written content, including text of notes and links, remains.
      if k=any(array[
        'object_path','file_path','image_path','image_url','photo_path',
        'photo_url','thumbnail_path','thumbnail_url','voice_path','voice_url',
        'audio_path','audio_url','video_path','video_url','media_path',
        'media_url','attachment_path','attachment_url','document_path',
        'document_url','mime_type','byte_size','base64','data_uri',
        'binary','blob','photo','photos','image','images','audio',
        'voice','video','videos','media','attachment','attachments',
        'file','files','document','documents','thumbnail','thumbnails'
      ]) then
        continue;
      end if;
      sanitized:=private.qa_structured_value(item.value);
      if sanitized is not null then
        result:=result||jsonb_build_object(item.key,sanitized);
      end if;
    end loop;
    return result;
  elsif typ='array' then
    result:='[]'::jsonb;
    for item in select value from jsonb_array_elements(p_value) loop
      sanitized:=private.qa_structured_value(item.value);
      -- Keep the array shape stable; a removed binary element becomes null.
      result:=result||jsonb_build_array(coalesce(sanitized,'null'::jsonb));
    end loop;
    return result;
  elsif typ='string' then
    if p_value #>> '{}' ~* '^\s*(data:(image|audio|video|application/(pdf|octet-stream))|blob:|file:|content://)' then
      return 'null'::jsonb;
    end if;
    -- Strip only the media URL inside a written sentence; do not discard
    -- surrounding notes, contact text or messages just because a link exists.
    -- Remove embedded media data URIs even when preceded by ordinary text.
    return to_jsonb(
      regexp_replace(
        regexp_replace(
          p_value #>> '{}',
          '(https?://[^[:space:]"<>]*/)?/storage/v1/object/[^[:space:]"<>]+',
          '[uploaded media excluded]','gi'),
        'data:(image|audio|video|application/(pdf|octet-stream))[^[:space:]"<>]*',
        '[uploaded media excluded]','gi')
    );
  end if;
  return p_value;
end $fn$;

revoke all on function private.qa_structured_value(jsonb) from public,anon,authenticated;
update public.personal_vault_records v set snapshot=private.qa_structured_value(v.snapshot),last_mirrored_at=now() where snapshot is distinct from private.qa_structured_value(v.snapshot);
update public.personal_vault_dependents v set snapshot=private.qa_structured_value(v.snapshot),last_mirrored_at=now() where snapshot is distinct from private.qa_structured_value(v.snapshot);
