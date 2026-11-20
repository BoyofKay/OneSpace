-- Reconciled 2026-11-20: applied to QA (ugwrpeduzyzrujkizqfo) on 2026-11-20 from
-- qa/activities-memories-two-scope-cutover-20261120:supabase/schema/0265_qa_closed_relationship_transaction_disabled.sql (original number 0265). Kept verbatim so the
-- repository replays to the live QA schema. QA only; never apply to Production.
-- QA staged ONLY. Relationship-end function is in private schema,
-- EXECUTE revoked, and additionally gated OFF. NOT callable by the app.
-- It deletes the former couple DB scope atomically, preserving both account
-- private scopes; physical Storage deletion requires a separate verified worker.
CREATE TABLE IF NOT EXISTS private.qa_relationship_v2_gate(
 id int PRIMARY KEY DEFAULT 1 CHECK(id=1),
 enabled boolean NOT NULL DEFAULT false
);
INSERT INTO private.qa_relationship_v2_gate(id,enabled) VALUES(1,false)
ON CONFLICT(id) DO UPDATE SET enabled=false;
REVOKE ALL ON private.qa_relationship_v2_gate FROM PUBLIC,anon,authenticated;

CREATE TABLE IF NOT EXISTS public.qa_shared_media_purge_queue(
 space_id uuid NOT NULL,
 bucket_id text NOT NULL,
 object_path text NOT NULL,
 queued_at timestamptz NOT NULL DEFAULT now(),
 deleted_at timestamptz,
 last_error text,
 PRIMARY KEY(space_id,bucket_id,object_path),
 CHECK(char_length(object_path) BETWEEN 1 AND 400),
 CHECK(bucket_id IN('onespace-note-images','onespace-memory-photos',
   'onespace-trip-documents','onespace-activity-media',
   'onespace-activity-voice','onespace-share-in'))
);
ALTER TABLE public.qa_shared_media_purge_queue ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.qa_shared_media_purge_queue FROM PUBLIC,anon,authenticated;
GRANT SELECT,UPDATE,DELETE ON public.qa_shared_media_purge_queue TO service_role;

CREATE OR REPLACE FUNCTION private.qa_close_relationship_v2(
 p_space uuid,p_action text,p_confirmation text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $q$
DECLARE me uuid:=auth.uid();
 owner_id uuid;participants uuid[];member_count int;
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
 SELECT s.created_by INTO owner_id FROM public.spaces s
   WHERE s.id=p_space FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Shared relationship no longer exists'
    USING ERRCODE='42501';END IF;
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
REVOKE ALL ON FUNCTION private.qa_close_relationship_v2(uuid,text,text)
 FROM PUBLIC,anon,authenticated,service_role;
-- No public RPC wrapper, no app button, no migration enabling the gate.
