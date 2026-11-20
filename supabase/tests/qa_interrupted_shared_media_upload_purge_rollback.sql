-- QA rollback: a valid shared Note/Memory/Trip Storage upload that fails
-- before its metadata row is saved must still be physically queued on breakup.
-- No existing pair is modified after rollback.
BEGIN;
SELECT set_config('qa.sp',(SELECT s.id::text FROM public.spaces s
 WHERE s.personal_owner IS NULL AND EXISTS(
  SELECT 1 FROM public.space_members m WHERE m.space_id=s.id
   AND m.user_id=s.created_by)
 AND (SELECT count(*) FROM public.space_members m WHERE m.space_id=s.id)=2
 LIMIT 1),true);
SELECT set_config('qa.owner',(SELECT created_by::text FROM public.spaces
 WHERE id=current_setting('qa.sp')::uuid),true);
SELECT set_config('request.jwt.claim.sub',current_setting('qa.owner'),true);
SET LOCAL ROLE authenticated;
INSERT INTO public.notes(space_id,created_by,title,visibility)
VALUES(current_setting('qa.sp')::uuid,current_setting('qa.owner')::uuid,
 'Unfinished Note upload','shared');
INSERT INTO public.memories(space_id,created_by,title,memory_date,visibility)
VALUES(current_setting('qa.sp')::uuid,current_setting('qa.owner')::uuid,
 'Unfinished memory photo',CURRENT_DATE,'shared');
INSERT INTO public.shared_trips(space_id,created_by,title,visibility)
VALUES(current_setting('qa.sp')::uuid,current_setting('qa.owner')::uuid,
 'Unfinished travel PDF','shared');
INSERT INTO public.notes(private_space_id,created_by,title,visibility)
VALUES(current_setting('qa.owner')::uuid,current_setting('qa.owner')::uuid,
 'Private note to keep','private');
RESET ROLE;
SELECT set_config('qa.note',(SELECT id::text FROM public.notes
 WHERE title='Unfinished Note upload' AND space_id=current_setting('qa.sp')::uuid LIMIT 1),true);
SELECT set_config('qa.memory',(SELECT id::text FROM public.memories
 WHERE title='Unfinished memory photo' AND space_id=current_setting('qa.sp')::uuid LIMIT 1),true);
SELECT set_config('qa.trip',(SELECT id::text FROM public.shared_trips
 WHERE title='Unfinished travel PDF' AND space_id=current_setting('qa.sp')::uuid LIMIT 1),true);
SELECT set_config('qa.private',(SELECT id::text FROM public.notes
 WHERE title='Private note to keep' AND private_space_id=current_setting('qa.owner')::uuid LIMIT 1),true);
INSERT INTO storage.objects(bucket_id,name,owner_id) VALUES
 ('onespace-note-images',current_setting('qa.note')||'/'||
  current_setting('qa.owner')||'/'||gen_random_uuid()::text||'.jpg',current_setting('qa.owner')),
 ('onespace-memory-photos',current_setting('qa.memory')||'/'||
  current_setting('qa.owner')||'/'||gen_random_uuid()::text||'.jpg',current_setting('qa.owner')),
 ('onespace-trip-documents',current_setting('qa.trip')||'/'||
  current_setting('qa.owner')||'/'||gen_random_uuid()::text||'.pdf',current_setting('qa.owner')),
 ('onespace-private-note-images',current_setting('qa.private')||'/'||
  current_setting('qa.owner')||'/'||gen_random_uuid()::text||'.jpg',current_setting('qa.owner'));
GRANT USAGE ON SCHEMA private TO authenticated;
GRANT EXECUTE ON FUNCTION private.qa_close_relationship_v2(uuid,text,text)
 TO authenticated;
UPDATE private.qa_relationship_v2_gate SET enabled=true WHERE id=1;
SELECT set_config('request.jwt.claim.sub',current_setting('qa.owner'),true);
SET LOCAL ROLE authenticated;
DO $separate$
DECLARE v jsonb;
BEGIN
 v:=private.qa_close_relationship_v2(current_setting('qa.sp')::uuid,
  'remove_partner','DELETE SHARED CONTENT');
 IF (v->>'media_files_queued')::integer<>3 THEN
  RAISE EXCEPTION 'Expected three orphaned shared attachments in purge queue: %',v;
 END IF;
END $separate$;
RESET ROLE;
DO $assert$
DECLARE n integer;
BEGIN
 SELECT count(*) INTO n FROM public.qa_shared_media_purge_queue q
 WHERE q.space_id=current_setting('qa.sp')::uuid
  AND q.expected_uploader_id=current_setting('qa.owner')::uuid
  AND q.bucket_id IN('onespace-note-images','onespace-memory-photos',
  'onespace-trip-documents') AND q.deleted_at IS NULL;
 IF n<>3 THEN RAISE EXCEPTION 'Shared interrupted media files were not queued';END IF;
 SELECT count(*) INTO n FROM public.notes
 WHERE id=current_setting('qa.private')::uuid
 AND private_space_id=current_setting('qa.owner')::uuid;
 IF n<>1 THEN RAISE EXCEPTION 'Owner private note was removed';END IF;
 SELECT count(*) INTO n FROM public.qa_shared_media_purge_queue q
 WHERE q.object_path LIKE current_setting('qa.private')||'/%';
 IF n<>0 THEN RAISE EXCEPTION 'Owner private photo queued as shared media';END IF;
END $assert$;
ROLLBACK;
SELECT 'PASS orphan shared Note/Memory/Trip files queued with real uploader while private media is untouched; rollback' result;