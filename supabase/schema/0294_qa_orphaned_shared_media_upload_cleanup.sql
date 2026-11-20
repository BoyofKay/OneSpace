-- Reconciled 2026-11-20: applied to QA (ugwrpeduzyzrujkizqfo) on 2026-11-20 from
-- qa/activities-memories-two-scope-cutover-20261120:supabase/schema/0287_qa_orphaned_shared_media_upload_cleanup.sql (original number 0287). Kept verbatim so the
-- repository replays to the live QA schema. QA only; never apply to Production.
-- QA: queued physical media must include orphan Storage objects from
-- uploads interrupted before metadata save. Not enabled for app users.
CREATE OR REPLACE FUNCTION private.qa_purge_queue_source_guard()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $q$
DECLARE uploader uuid;storage_owner text;filename_owner text;
BEGIN
 IF tg_op='UPDATE' THEN
  IF new.space_id IS DISTINCT FROM old.space_id
    OR new.bucket_id IS DISTINCT FROM old.bucket_id
    OR new.object_path IS DISTINCT FROM old.object_path
    OR new.expected_uploader_id IS DISTINCT FROM old.expected_uploader_id THEN
   RAISE EXCEPTION 'Cannot change queued media identity or provenance'
    USING ERRCODE='42501';
  END IF;
  RETURN new;
 END IF;
 IF new.bucket_id IN('onespace-note-images','onespace-memory-photos',
   'onespace-trip-documents','onespace-activity-media','onespace-activity-voice')
  AND new.object_path !~ '^[0-9a-f-]{36}/[0-9a-f-]{36}/[0-9a-f-]{36}[.](jpg|jpeg|png|webp|m4a|pdf)$' THEN
   RAISE EXCEPTION 'Unsupported relationship media path' USING ERRCODE='42501';
 END IF;
 IF new.bucket_id='onespace-share-in' AND
   new.object_path !~ '^[0-9a-f-]{36}/[0-9a-f-]{36}[.](jpg|jpeg|png|webp|heic|pdf)$' THEN
   RAISE EXCEPTION 'Unsupported shared inbox media path' USING ERRCODE='42501';
 END IF;
 IF new.bucket_id='onespace-note-images' THEN
  SELECT i.created_by INTO uploader FROM public.note_images i
   JOIN public.notes parent ON parent.id=i.note_id
   WHERE i.object_path=new.object_path AND i.storage_bucket_id=new.bucket_id
    AND parent.space_id=new.space_id AND parent.private_space_id IS NULL;
 ELSIF new.bucket_id='onespace-memory-photos' THEN
  SELECT i.created_by INTO uploader FROM public.memory_photos i
   JOIN public.memories parent ON parent.id=i.memory_id
   WHERE i.object_path=new.object_path AND i.storage_bucket_id=new.bucket_id
    AND parent.space_id=new.space_id AND parent.private_space_id IS NULL;
 ELSIF new.bucket_id='onespace-trip-documents' THEN
  SELECT i.created_by INTO uploader FROM public.trip_attachments i
   JOIN public.shared_trips parent ON parent.id=i.trip_id
   WHERE i.object_path=new.object_path AND i.storage_bucket_id=new.bucket_id
    AND parent.space_id=new.space_id AND parent.private_space_id IS NULL;
 ELSIF new.bucket_id IN('onespace-activity-media','onespace-activity-voice') THEN
  SELECT nullif(o.owner_id,'')::uuid INTO uploader FROM storage.objects o
   JOIN public.activities a ON a.id::text=split_part(o.name,'/',1)
   WHERE o.bucket_id=new.bucket_id AND o.name=new.object_path
    AND a.space_id=new.space_id AND a.private_space_id IS NULL
    AND o.owner_id ~ '^[0-9a-f-]{36}$';
 ELSIF new.bucket_id='onespace-share-in' THEN
  SELECT i.created_by INTO uploader FROM public.items_to_sort i
   WHERE i.space_id=new.space_id AND i.private_space_id IS NULL
    AND i.file_path=new.object_path AND i.created_by::text=split_part(i.file_path,'/',1);
 ELSE
  RAISE EXCEPTION 'Unknown relationship media bucket' USING ERRCODE='42501';
 END IF;
 -- Resolve interrupted Storage uploads without attachment metadata.
 -- Only a real Storage object whose owner UUID matches the original path,
 -- currently in the same pair and parent namespace, may be queued.
 IF uploader IS NULL AND new.bucket_id IN(
  'onespace-note-images','onespace-memory-photos','onespace-trip-documents') THEN
  SELECT o.owner_id::uuid INTO uploader FROM storage.objects o
  WHERE o.bucket_id=new.bucket_id AND o.name=new.object_path
    AND o.owner_id ~ '^[0-9a-f-]{36}$'
    AND o.owner_id=split_part(o.name,'/',2)
    AND (
      (o.bucket_id='onespace-note-images'
       AND EXISTS(SELECT 1 FROM public.notes parent
        WHERE parent.id::text=split_part(o.name,'/',1)
         AND parent.space_id=new.space_id AND parent.private_space_id IS NULL)
       AND NOT EXISTS(SELECT 1 FROM public.note_images i
        WHERE i.storage_bucket_id=o.bucket_id AND i.object_path=o.name))
      OR
      (o.bucket_id='onespace-memory-photos'
       AND EXISTS(SELECT 1 FROM public.memories parent
        WHERE parent.id::text=split_part(o.name,'/',1)
         AND parent.space_id=new.space_id AND parent.private_space_id IS NULL)
       AND NOT EXISTS(SELECT 1 FROM public.memory_photos i
        WHERE i.storage_bucket_id=o.bucket_id AND i.object_path=o.name))
      OR
      (o.bucket_id='onespace-trip-documents'
       AND EXISTS(SELECT 1 FROM public.shared_trips parent
        WHERE parent.id::text=split_part(o.name,'/',1)
         AND parent.space_id=new.space_id AND parent.private_space_id IS NULL)
       AND NOT EXISTS(SELECT 1 FROM public.trip_attachments i
        WHERE i.storage_bucket_id=o.bucket_id AND i.object_path=o.name))
    )
  LIMIT 1;
 END IF;
 IF uploader IS NULL OR NOT EXISTS(SELECT 1 FROM public.space_members m
   WHERE m.space_id=new.space_id AND m.user_id=uploader) THEN
  RAISE EXCEPTION 'Queued shared file author is not a current member'
   USING ERRCODE='42501';
 END IF;
 filename_owner:=CASE WHEN new.bucket_id='onespace-share-in'
  THEN split_part(new.object_path,'/',1) ELSE split_part(new.object_path,'/',2) END;
 IF filename_owner<>uploader::text THEN
  RAISE EXCEPTION 'File prefix does not belong to its recorded author'
   USING ERRCODE='42501';
 END IF;
 SELECT o.owner_id INTO storage_owner FROM storage.objects o
  WHERE o.bucket_id=new.bucket_id AND o.name=new.object_path;
 IF storage_owner IS NOT NULL AND storage_owner<>uploader::text THEN
  RAISE EXCEPTION 'File object was uploaded by another account'
   USING ERRCODE='42501';
 END IF;
 new.expected_uploader_id:=uploader;
 RETURN new;
END $q$;
CREATE OR REPLACE FUNCTION private.qa_close_relationship_v2(
 p_space uuid,p_action text,p_confirmation text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $q$
DECLARE me uuid:=auth.uid();
 owner_id uuid;legacy_personal_owner uuid;participants uuid[];member_count int;
 rec record;before_count bigint;after_count bigint;
 before_counts jsonb:='{}'::jsonb;file_count int;
BEGIN
 IF NOT EXISTS(SELECT 1 FROM private.qa_relationship_v2_gate g
   WHERE g.id=1 AND g.enabled) THEN
  RAISE EXCEPTION 'OneSpace relationship deletion is not enabled'
   USING ERRCODE='42501';
 END IF;
 IF me IS NULL OR p_space IS NULL OR
  p_confirmation IS DISTINCT FROM 'DELETE SHARED CONTENT' OR
  p_action NOT IN('remove_partner','leave_space','delete_space') THEN
  RAISE EXCEPTION 'Signed-in account, existing space and explicit irreversible confirmation are required'
    USING ERRCODE='42501';
 END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(p_space::text,0));
 SELECT s.created_by,s.personal_owner INTO owner_id,legacy_personal_owner FROM public.spaces s
   WHERE s.id=p_space FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Shared relationship no longer exists'
    USING ERRCODE='42501';END IF;
 IF legacy_personal_owner IS NOT NULL THEN
  RAISE EXCEPTION 'Personal solo spaces cannot be removed by couple lifecycle operations'
   USING ERRCODE='42501';
 END IF;
 SELECT count(*),array_agg(user_id ORDER BY user_id) INTO member_count,participants
 FROM public.space_members WHERE space_id=p_space;
 IF member_count NOT BETWEEN 1 AND 2 OR me<>ALL(participants) THEN
   RAISE EXCEPTION 'Account does not belong to this current space'
    USING ERRCODE='42501';
 END IF;
 IF p_action='remove_partner' AND (me<>owner_id OR member_count<>2) THEN
   RAISE EXCEPTION 'Only the paired owner can remove their current partner'
     USING ERRCODE='42501';END IF;
 IF p_action='leave_space' AND (me=owner_id OR member_count<>2) THEN
   RAISE EXCEPTION 'Only the invited partner can leave this paired space'
     USING ERRCODE='42501';END IF;
 IF p_action='delete_space' AND me<>owner_id THEN
   RAISE EXCEPTION 'Only the owner can delete their shared space'
     USING ERRCODE='42501';END IF;
 IF (SELECT count(*) FROM public.user_private_spaces ps
   WHERE ps.owner_id=ANY(participants))<>member_count THEN
   RAISE EXCEPTION 'Cannot separate: an account-owned personal namespace is missing'
    USING ERRCODE='42501';END IF;
 -- Preserve all private families, including those without an active UI.
 FOR rec IN
  SELECT c.table_name FROM information_schema.columns c
  WHERE c.table_schema='public'
  GROUP BY c.table_name HAVING bool_or(c.column_name='private_space_id')
 LOOP
  EXECUTE format('SELECT count(*) FROM public.%I WHERE private_space_id=ANY($1)',
    rec.table_name) INTO before_count USING participants;
  before_counts:=before_counts||jsonb_build_object(rec.table_name,before_count);
 END LOOP;

 -- Capture authorized couple media pointers before parent cascading deletes.
 INSERT INTO public.qa_shared_media_purge_queue(space_id,bucket_id,object_path)
 SELECT p_space,'onespace-note-images',n.object_path FROM public.note_images n
 JOIN public.notes parent ON parent.id=n.note_id
 WHERE parent.space_id=p_space AND parent.private_space_id IS NULL
   AND n.storage_bucket_id='onespace-note-images'
 ON CONFLICT DO NOTHING;
 INSERT INTO public.qa_shared_media_purge_queue(space_id,bucket_id,object_path)
 SELECT p_space,'onespace-memory-photos',f.object_path FROM public.memory_photos f
 JOIN public.memories parent ON parent.id=f.memory_id
 WHERE parent.space_id=p_space AND parent.private_space_id IS NULL
   AND f.storage_bucket_id='onespace-memory-photos'
 ON CONFLICT DO NOTHING;
 INSERT INTO public.qa_shared_media_purge_queue(space_id,bucket_id,object_path)
 SELECT p_space,'onespace-trip-documents',d.object_path FROM public.trip_attachments d
 JOIN public.shared_trips parent ON parent.id=d.trip_id
 WHERE parent.space_id=p_space AND parent.private_space_id IS NULL
   AND d.storage_bucket_id='onespace-trip-documents'
 ON CONFLICT DO NOTHING;
 -- Include interrupted note, memory and trip uploads that lack a
 -- committed metadata row. Guard checks ownership, provenance and pair.
 INSERT INTO public.qa_shared_media_purge_queue(space_id,bucket_id,object_path)
 SELECT p_space,o.bucket_id,o.name FROM storage.objects o
 WHERE o.bucket_id IN(
  'onespace-note-images','onespace-memory-photos','onespace-trip-documents')
  AND (
   (o.bucket_id='onespace-note-images' AND EXISTS(
      SELECT 1 FROM public.notes parent
      WHERE parent.id::text=split_part(o.name,'/',1)
      AND parent.space_id=p_space AND parent.private_space_id IS NULL))
   OR (o.bucket_id='onespace-memory-photos' AND EXISTS(
      SELECT 1 FROM public.memories parent
      WHERE parent.id::text=split_part(o.name,'/',1)
      AND parent.space_id=p_space AND parent.private_space_id IS NULL))
   OR (o.bucket_id='onespace-trip-documents' AND EXISTS(
      SELECT 1 FROM public.shared_trips parent
      WHERE parent.id::text=split_part(o.name,'/',1)
      AND parent.space_id=p_space AND parent.private_space_id IS NULL))
  )
 ON CONFLICT DO NOTHING;
 INSERT INTO public.qa_shared_media_purge_queue(space_id,bucket_id,object_path)
 SELECT p_space,o.bucket_id,o.name FROM storage.objects o
 WHERE o.bucket_id IN('onespace-activity-media','onespace-activity-voice')
  AND EXISTS(SELECT 1 FROM public.activities a
   WHERE a.id::text=split_part(o.name,'/',1)
    AND a.space_id=p_space AND a.private_space_id IS NULL)
 ON CONFLICT DO NOTHING;
 INSERT INTO public.qa_shared_media_purge_queue(space_id,bucket_id,object_path)
 SELECT p_space,'onespace-share-in',i.file_path FROM public.items_to_sort i
 WHERE i.space_id=p_space AND i.private_space_id IS NULL
   AND i.file_path IS NOT NULL
 ON CONFLICT DO NOTHING;
 SELECT count(*) INTO file_count
  FROM public.qa_shared_media_purge_queue
  WHERE space_id=p_space AND deleted_at IS NULL;
 DELETE FROM public.spaces s WHERE s.id=p_space;
 IF NOT FOUND THEN RAISE EXCEPTION 'Relationship deletion failed; rolled back'
  USING ERRCODE='42501';END IF;
 IF EXISTS(SELECT 1 FROM public.space_members WHERE space_id=p_space) THEN
  RAISE EXCEPTION 'Former pair membership remains; rolled back'
   USING ERRCODE='42501';END IF;
 IF (SELECT count(*) FROM public.user_private_spaces ps
   WHERE ps.owner_id=ANY(participants))<>member_count THEN
  RAISE EXCEPTION 'Personal namespace was lost; entire deletion rolled back'
   USING ERRCODE='42501';END IF;
 FOR rec IN
  SELECT c.table_name FROM information_schema.columns c
  WHERE c.table_schema='public'
  GROUP BY c.table_name HAVING bool_or(c.column_name='private_space_id')
 LOOP
  EXECUTE format('SELECT count(*) FROM public.%I WHERE private_space_id=ANY($1)',
   rec.table_name) INTO after_count USING participants;
  IF after_count IS DISTINCT FROM (before_counts->>rec.table_name)::bigint THEN
   RAISE EXCEPTION 'Personal content count changed in %, entire deletion rolled back',
    rec.table_name USING ERRCODE='42501';
  END IF;
 END LOOP;
 RETURN jsonb_build_object('status','shared_db_removed_storage_purge_pending',
  'space_id',p_space,'members_unpaired',member_count,
  'media_files_queued',file_count,'action',p_action);
END $q$;