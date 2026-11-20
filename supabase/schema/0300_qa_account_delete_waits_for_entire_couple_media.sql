-- Reconciled 2026-11-20: applied to QA (ugwrpeduzyzrujkizqfo) on 2026-11-20 from
-- qa/activities-memories-two-scope-cutover-20261120:supabase/schema/0293_qa_account_delete_waits_for_entire_couple_media.sql (original number 0293). Kept verbatim so the
-- repository replays to the live QA schema. QA only; never apply to Production.
-- QA lifecycle: a deleting account must not be finalized while the
-- former couple's Storage media (including uploads by their partner) remains.
-- No real account deletion, no gate enabling, no Production changes.
ALTER TABLE public.account_deletion_requests
 ADD COLUMN IF NOT EXISTS closing_space_id uuid;
-- Intentionally no FK: the shared space itself is physically removed first.
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
 -- Retain relationship provenance for any member with an active account
 -- deletion request, including requests still in the cancellable grace.
 -- The finalizer must await BOTH partners' shared Storage bytes, not just
 -- files owned by the account currently being deleted.
 UPDATE public.account_deletion_requests r SET closing_space_id=p_space
 WHERE r.user_id=ANY(participants)
   AND r.cancelled_at IS NULL AND r.completed_at IS NULL;
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
CREATE OR REPLACE FUNCTION public.qa_due_account_close_current_relationship(p_user uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $q$
DECLARE due_date timestamptz;sp uuid;owner_id uuid;num_pairs integer;
 prev_claim text:=current_setting('request.jwt.claim.sub',true);
 action_name text;result jsonb;
BEGIN
 IF current_user<>'service_role' THEN
  RAISE EXCEPTION 'Only the service may close an overdue account relationship'
   USING ERRCODE='42501';
 END IF;
 IF p_user IS NULL THEN
  RAISE EXCEPTION 'User id required' USING ERRCODE='22023';
 END IF;
 IF NOT EXISTS(SELECT 1 FROM private.qa_account_v2_gate
  WHERE id=1 AND enabled) OR NOT EXISTS(
  SELECT 1 FROM private.qa_relationship_v2_gate WHERE id=1 AND enabled) THEN
  RAISE EXCEPTION 'Due account relationship closure is not enabled'
    USING ERRCODE='42501';
 END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(p_user::text,5));
 SELECT r.purge_after INTO due_date
 FROM public.account_deletion_requests r
 WHERE r.user_id=p_user AND r.cancelled_at IS NULL
   AND r.completed_at IS NULL AND r.processing_at IS NULL
   AND r.purge_after<=now()
 FOR UPDATE;
 IF due_date IS NULL THEN
  RAISE EXCEPTION 'Cannot close a relationship during the cancellable grace'
    USING ERRCODE='42501';
 END IF;
 IF NOT EXISTS(SELECT 1 FROM public.user_private_spaces p
     WHERE p.owner_id=p_user) THEN
  RAISE EXCEPTION 'Due account private namespace missing'
    USING ERRCODE='42501';
 END IF;
 SELECT count(*),(array_agg(s.id))[1],(array_agg(s.created_by))[1] INTO num_pairs,sp,owner_id
 FROM public.space_members m JOIN public.spaces s ON s.id=m.space_id
 WHERE m.user_id=p_user AND s.personal_owner IS NULL;
 IF num_pairs>1 THEN
  RAISE EXCEPTION 'Multiple relationships need manual reconciliation'
    USING ERRCODE='42501';
 END IF;
 IF num_pairs=0 THEN
  RETURN jsonb_build_object('status','already_unpaired',
    'shared_deleted',false,'private_namespace_preserved',true);
 END IF;
 action_name:=CASE WHEN owner_id=p_user THEN 'delete_space'
  ELSE 'leave_space' END;
 -- The SECURITY DEFINER relationship function already validates that the
 -- actor is the signed-in owner/invited partner, the exact current pair,
 -- deletion phrase, and *all* account-private root row count preservation.
 PERFORM set_config('request.jwt.claim.sub',p_user::text,true);
 result:=private.qa_close_relationship_v2(
  sp,action_name,'DELETE SHARED CONTENT');
 UPDATE public.account_deletion_requests r SET closing_space_id=sp
 WHERE r.user_id=p_user AND r.cancelled_at IS NULL AND r.completed_at IS NULL
  AND r.purge_after<=now() AND r.processing_at IS NULL;
 PERFORM set_config('request.jwt.claim.sub',coalesce(prev_claim,''),true);
 IF EXISTS(SELECT 1 FROM public.space_members m WHERE m.user_id=p_user
     AND m.space_id=sp) OR
  NOT EXISTS(SELECT 1 FROM public.user_private_spaces p
     WHERE p.owner_id=p_user) THEN
  RAISE EXCEPTION 'Relationship close failed to unpair or preserve private data'
    USING ERRCODE='42501';
 END IF;
 RETURN result||jsonb_build_object('due_user_id',p_user,
  'closed_on_behalf_of_due_account',true);
END $q$;
CREATE OR REPLACE FUNCTION public.qa_account_final_deletion_readiness(p_user uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $q$
DECLARE gate_on boolean; preflight jsonb;remaining_objects bigint;
 path_references bigint;unfinished_private_jobs bigint;unfinished_shared_jobs bigint;
 due boolean; fk_count bigint;member_count bigint;created_count bigint;
 legacy_count bigint;personal_exists boolean;ready boolean;closed_space uuid;
 remaining_shared_storage_objects bigint;
BEGIN
 IF current_user<>'service_role' THEN
  RAISE EXCEPTION 'Service-only account final readiness' USING ERRCODE='42501';
 END IF;
 IF p_user IS NULL THEN
  RAISE EXCEPTION 'Account user required' USING ERRCODE='22023';
 END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(p_user::text,1));
 SELECT enabled INTO gate_on FROM private.qa_account_v2_gate WHERE id=1;
 -- This gate must be explicitly opened only in isolated QA rollback tests
 -- until finalization and independent device verification are complete.
 IF NOT coalesce(gate_on,false) THEN
  RAISE EXCEPTION 'Account finalization gate closed' USING ERRCODE='42501';
 END IF;
 preflight:=public.qa_account_finalizer_preflight(p_user);
 due:=coalesce((preflight->>'due')::boolean,false);
 member_count:=coalesce((preflight->>'member_spaces')::bigint,0);
 created_count:=coalesce((preflight->>'spaces_created')::bigint,0);
 legacy_count:=coalesce((preflight->>'legacy_couple_private_rows')::bigint,0);
 fk_count:=coalesce((preflight->>'unresolved_no_action_user_references')::bigint,0);
 personal_exists:=coalesce((preflight->>'private_namespace_exists')::boolean,false);

 SELECT count(*) INTO remaining_objects FROM storage.objects o
 WHERE o.owner_id=p_user::text;
 -- A service-created object with NULL/different Storage ownership must
 -- not be silently orphaned when its path still contains the deleted owner.
 SELECT count(*) INTO path_references FROM storage.objects o
 WHERE p_user::text=ANY(storage.foldername(o.name));
 SELECT count(*) INTO unfinished_private_jobs
 FROM public.qa_account_private_media_purge_queue q
 WHERE q.owner_id=p_user AND q.deleted_at IS NULL;
 SELECT r.closing_space_id INTO closed_space
 FROM public.account_deletion_requests r
 WHERE r.user_id=p_user AND r.cancelled_at IS NULL AND r.completed_at IS NULL;
 SELECT count(*) INTO unfinished_shared_jobs
 FROM public.qa_shared_media_purge_queue q
 WHERE (q.expected_uploader_id=p_user OR
   (closed_space IS NOT NULL AND q.space_id=closed_space))
  AND q.deleted_at IS NULL;
 -- Even an acknowledged job cannot count as deleted if physical bytes remain,
 -- including objects uploaded by the surviving partner.
 SELECT count(*) INTO remaining_shared_storage_objects
 FROM public.qa_shared_media_purge_queue q
 JOIN storage.objects o ON o.bucket_id=q.bucket_id AND o.name=q.object_path
 WHERE closed_space IS NOT NULL AND q.space_id=closed_space;
 ready:=due AND personal_exists AND member_count=0 AND created_count=0
  AND legacy_count=0 AND fk_count=0
  AND remaining_objects=0 AND path_references=0
  AND unfinished_private_jobs=0 AND unfinished_shared_jobs=0
  AND remaining_shared_storage_objects=0;
 RETURN jsonb_build_object(
  'ready_for_auth_delete',ready,'due',due,
  'private_namespace_exists',personal_exists,
  'remaining_relationship_memberships',member_count,
  'remaining_created_spaces',created_count,
  'legacy_couple_private_rows',legacy_count,
  'unresolved_auth_user_fk_references',fk_count,
  'remaining_storage_objects_owned',remaining_objects,
  'remaining_storage_folder_references',path_references,
  'unfinished_private_file_purges',unfinished_private_jobs,
  'unfinished_shared_file_purges',unfinished_shared_jobs,
  'remaining_shared_storage_objects',remaining_shared_storage_objects,
  'closed_relationship_space_id',closed_space,
  'actual_auth_deletion_not_implemented',true);
END $q$;
CREATE OR REPLACE FUNCTION public.qa_scrub_completed_account_media_jobs(p_user uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $q$
DECLARE verified jsonb;own_count integer;shared_count integer;
BEGIN
 IF current_user<>'service_role' THEN
  RAISE EXCEPTION 'Service-only completed account media audit cleanup'
   USING ERRCODE='42501';
 END IF;
 IF p_user IS NULL THEN RAISE EXCEPTION 'Owner required' USING ERRCODE='22023';END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(p_user::text,1));
 verified:=public.qa_account_final_deletion_readiness(p_user);
 IF verified->>'ready_for_auth_delete'<>'true' THEN
  RAISE EXCEPTION 'Cannot clear any audit while account deletion prerequisites remain'
   USING ERRCODE='42501';
 END IF;
 DELETE FROM public.qa_account_private_media_purge_queue q
 WHERE q.owner_id=p_user AND q.deleted_at IS NOT NULL;
 GET DIAGNOSTICS own_count=ROW_COUNT;
 DELETE FROM public.qa_shared_media_purge_queue q
 WHERE q.deleted_at IS NOT NULL AND (
  q.expected_uploader_id=p_user OR EXISTS(
   SELECT 1 FROM public.account_deletion_requests r
   WHERE r.user_id=p_user AND r.closing_space_id=q.space_id
    AND r.cancelled_at IS NULL AND r.completed_at IS NULL
  )
 );
 GET DIAGNOSTICS shared_count=ROW_COUNT;
 RETURN jsonb_build_object('completed_private_jobs_scrubbed',own_count,
  'completed_shared_jobs_scrubbed',shared_count,
  'account_user_deleted',false);
END $q$;
