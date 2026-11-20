-- QA 0308: fix the attachment immutability trigger from 0265.
--
-- Before: the function read old.note_id inside "tg_table_name='note_images' AND
-- old.note_id ...". PL/pgSQL resolves record fields even when the first test is
-- false, so EVERY client update of a memory_photos or trip_attachments row
-- failed with 'record "old" has no field "note_id"'. Removing a Memory photo,
-- editing its caption or reordering photos, and editing travel documents, all
-- broke in QA. Found by qa_personal_media_storage_access.sql.
-- Rules are unchanged: bucket, path, author, id and parent stay immutable.
-- QA only; never apply to Production.

CREATE OR REPLACE FUNCTION private.qa_attachment_scope_immutable()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $q$
DECLARE parent_column text;
BEGIN
 IF current_user NOT IN ('authenticated','anon') THEN RETURN new;END IF;
 IF tg_op<>'UPDATE' THEN RETURN new;END IF;
 IF old.storage_bucket_id IS DISTINCT FROM new.storage_bucket_id OR
    old.object_path IS DISTINCT FROM new.object_path OR
    old.created_by IS DISTINCT FROM new.created_by OR
    old.id IS DISTINCT FROM new.id THEN
   RAISE EXCEPTION 'Attachment ownership and storage path are immutable' USING ERRCODE='42501';
 END IF;
 parent_column:=CASE tg_table_name
   WHEN 'note_images' THEN 'note_id'
   WHEN 'memory_photos' THEN 'memory_id'
   WHEN 'trip_attachments' THEN 'trip_id' END;
 IF parent_column IS NOT NULL AND
    (to_jsonb(old)->>parent_column) IS DISTINCT FROM (to_jsonb(new)->>parent_column) THEN
   RAISE EXCEPTION 'Attachment parent cannot change' USING ERRCODE='42501';
 END IF;
 RETURN new;
END $q$;
REVOKE ALL ON FUNCTION private.qa_attachment_scope_immutable() FROM PUBLIC,anon,authenticated;
