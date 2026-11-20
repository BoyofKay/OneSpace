-- QA only: gate and permissions are opened ONLY inside this transaction.
-- No real relationship/account or Storage object is committed/deleted.
BEGIN;
GRANT USAGE ON SCHEMA private TO authenticated;
GRANT EXECUTE ON FUNCTION private.qa_close_relationship_v2(uuid,text,text)
 TO authenticated;
SELECT set_config('qa.space',(SELECT s.id::text FROM public.spaces s
 WHERE EXISTS(SELECT 1 FROM public.space_members m
 WHERE m.space_id=s.id AND m.user_id=s.created_by)
 AND (SELECT count(*) FROM public.space_members m WHERE m.space_id=s.id)=2
 ORDER BY s.id LIMIT 1),true);
SELECT set_config('qa.owner',(SELECT created_by::text FROM public.spaces
 WHERE id=current_setting('qa.space')::uuid),true);
SELECT set_config('qa.peer',(SELECT user_id::text FROM public.space_members
 WHERE space_id=current_setting('qa.space')::uuid
 AND user_id::text<>current_setting('qa.owner') LIMIT 1),true);
SELECT set_config('qa.outside',(SELECT user_id::text FROM public.space_members
 WHERE space_id<>current_setting('qa.space')::uuid LIMIT 1),true);
SELECT set_config('request.jwt.claim.sub',current_setting('qa.owner'),true);
SET LOCAL ROLE authenticated;
DO $gate$
BEGIN
 BEGIN
  PERFORM private.qa_close_relationship_v2(current_setting('qa.space')::uuid,
    'remove_partner','DELETE SHARED CONTENT');
  RAISE EXCEPTION 'BUG: disabled destructive service executed';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM LIKE 'BUG:%' THEN RAISE;END IF;END;
END $gate$;
RESET ROLE;
UPDATE private.qa_relationship_v2_gate SET enabled=true WHERE id=1;
SET LOCAL ROLE authenticated;
DO $fixtures$
DECLARE owner_id uuid:=current_setting('qa.owner')::uuid;
 peer uuid:=current_setting('qa.peer')::uuid;
 sp uuid:=current_setting('qa.space')::uuid;
 note_a uuid;note_b uuid;shared_note uuid;image_path text;
BEGIN
 IF owner_id IS NULL OR peer IS NULL OR sp IS NULL THEN RAISE EXCEPTION 'QA pair missing';END IF;
 INSERT INTO public.notes(private_space_id,created_by,title,visibility)
 VALUES(owner_id,owner_id,'QA owner personal untouched','private')
 RETURNING id INTO note_a;
 INSERT INTO public.notes(space_id,created_by,title,visibility)
 VALUES(sp,owner_id,'QA shared note to delete','shared')
 RETURNING id INTO shared_note;
 image_path:=shared_note::text||'/'||owner_id::text||'/'||gen_random_uuid()::text||'.jpg';
 INSERT INTO storage.objects(bucket_id,name,owner_id)
 VALUES('onespace-note-images',image_path,owner_id::text);
 INSERT INTO public.note_images(note_id,created_by,object_path,storage_bucket_id)
 VALUES(shared_note,owner_id,image_path,'onespace-note-images');
 PERFORM set_config('qa.note_shared',shared_note::text,true);
 PERFORM set_config('qa.owner_private',note_a::text,true);
 PERFORM set_config('qa.shared_path',image_path,true);
 PERFORM set_config('request.jwt.claim.sub',peer::text,true);
 INSERT INTO public.notes(private_space_id,created_by,title,visibility)
 VALUES(peer,peer,'QA peer personal untouched','private') RETURNING id INTO note_b;
 PERFORM set_config('qa.peer_private',note_b::text,true);
END $fixtures$;
DO $actor_guards$
BEGIN
 PERFORM set_config('request.jwt.claim.sub',current_setting('qa.outside'),true);
 BEGIN
  PERFORM private.qa_close_relationship_v2(current_setting('qa.space')::uuid,
     'remove_partner','DELETE SHARED CONTENT');
  RAISE EXCEPTION 'BUG: outsider separated unrelated couple';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM LIKE 'BUG:%' THEN RAISE;END IF;END;
 PERFORM set_config('request.jwt.claim.sub',current_setting('qa.peer'),true);
 BEGIN
  PERFORM private.qa_close_relationship_v2(current_setting('qa.space')::uuid,
     'delete_space','DELETE SHARED CONTENT');
  RAISE EXCEPTION 'BUG: invited partner deleted owner space';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM LIKE 'BUG:%' THEN RAISE;END IF;END;
 PERFORM set_config('request.jwt.claim.sub',current_setting('qa.owner'),true);
 BEGIN
  PERFORM private.qa_close_relationship_v2(current_setting('qa.space')::uuid,
     'leave_space','DELETE SHARED CONTENT');
  RAISE EXCEPTION 'BUG: owner used invited partner leave action';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM LIKE 'BUG:%' THEN RAISE;END IF;END;
 BEGIN
  PERFORM private.qa_close_relationship_v2(current_setting('qa.space')::uuid,
     'remove_partner','NO');
  RAISE EXCEPTION 'BUG: incomplete irreversible confirmation accepted';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM LIKE 'BUG:%' THEN RAISE;END IF;END;
END $actor_guards$;
DO $execute$
DECLARE result jsonb;n int;
BEGIN
 result:=private.qa_close_relationship_v2(current_setting('qa.space')::uuid,
  'remove_partner','DELETE SHARED CONTENT');
 IF result->>'status'<>'shared_db_removed_storage_purge_pending'
  OR (result->>'media_files_queued')::int<1 THEN
   RAISE EXCEPTION 'Deletion did not capture shared media cleanup queue';END IF;
 BEGIN
  SELECT count(*) INTO n FROM public.qa_shared_media_purge_queue
  WHERE space_id=current_setting('qa.space')::uuid;
  RAISE EXCEPTION 'BUG: client can read privileged physical purge queue';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM LIKE 'BUG:%' THEN RAISE;END IF;END;
 SELECT count(*) INTO n FROM public.notes WHERE id=current_setting('qa.note_shared')::uuid;
 IF n<>0 THEN RAISE EXCEPTION 'Former couple shared data not erased';END IF;
 SELECT count(*) INTO n FROM public.notes WHERE id=current_setting('qa.owner_private')::uuid;
 IF n<>1 THEN RAISE EXCEPTION 'Owner personal Notes lost';END IF;
 SELECT count(*) INTO n FROM public.user_private_spaces
 WHERE owner_id IN(current_setting('qa.owner')::uuid,current_setting('qa.peer')::uuid);
 IF n<>2 THEN RAISE EXCEPTION 'Private namespaces not preserved';END IF;
 PERFORM set_config('request.jwt.claim.sub',current_setting('qa.peer'),true);
 SELECT count(*) INTO n FROM public.notes WHERE id=current_setting('qa.peer_private')::uuid;
 IF n<>1 THEN RAISE EXCEPTION 'Surviving partner private data lost';END IF;
 SELECT count(*) INTO n FROM public.notes WHERE id=current_setting('qa.owner_private')::uuid;
 IF n<>0 THEN RAISE EXCEPTION 'Surviving partner sees owner private Note';END IF;
 SELECT count(*) INTO n FROM storage.objects WHERE name=current_setting('qa.shared_path');
 IF n<>0 THEN RAISE EXCEPTION 'Old couple media still visible to surviving partner';END IF;
END $execute$;
RESET ROLE;
DO $queue$
DECLARE n int;
BEGIN
 SELECT count(*) INTO n FROM public.qa_shared_media_purge_queue
 WHERE space_id=current_setting('qa.space')::uuid
 AND object_path=current_setting('qa.shared_path') AND deleted_at IS NULL;
 IF n<>1 THEN RAISE EXCEPTION 'Shared file not queued for physical purge';END IF;
END $queue$;
ROLLBACK;
SELECT 'PASS closed gate, outsider/role/confirmation rejection, shared DB erasure, queued media, two personal namespaces and account privacy; all rolled back' result;