-- QA ONLY. Prepare the owner-private file inventory for a due 7-day account
-- purge. Nothing in this migration deletes a file, namespace or Auth user.
-- The gate is OFF and no app role can call this private service-only function.
CREATE TABLE IF NOT EXISTS private.qa_account_v2_gate(
 id integer PRIMARY KEY DEFAULT 1 CHECK(id=1),
 enabled boolean NOT NULL DEFAULT false
);
INSERT INTO private.qa_account_v2_gate(id,enabled) VALUES(1,false)
ON CONFLICT(id) DO UPDATE SET enabled=false;
REVOKE ALL ON private.qa_account_v2_gate FROM PUBLIC,anon,authenticated;

CREATE TABLE IF NOT EXISTS public.qa_account_private_media_purge_queue(
 owner_id uuid NOT NULL,
 bucket_id text NOT NULL,
 object_path text NOT NULL,
 queued_at timestamptz NOT NULL DEFAULT now(),
 deleted_at timestamptz,
 lease_id uuid,
 leased_at timestamptz,
 attempts integer NOT NULL DEFAULT 0 CHECK(attempts>=0),
 last_error text,
 PRIMARY KEY(owner_id,bucket_id,object_path),
 CHECK(bucket_id IN('onespace-private-note-images',
   'onespace-private-memory-photos','onespace-private-trip-documents',
   'onespace-private-share-in')),
 CHECK(char_length(object_path) BETWEEN 1 AND 400)
);
ALTER TABLE public.qa_account_private_media_purge_queue ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.qa_account_private_media_purge_queue FROM PUBLIC,anon,authenticated;
GRANT SELECT,INSERT,UPDATE ON public.qa_account_private_media_purge_queue TO service_role;

CREATE OR REPLACE FUNCTION private.qa_inventory_due_private_media(p_user uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $q$
DECLARE deadline timestamptz;found_rows integer;queued integer;
BEGIN
 IF current_user<>'service_role' THEN
  RAISE EXCEPTION 'Service-only due account inventory' USING ERRCODE='42501';
 END IF;
 IF NOT EXISTS(SELECT 1 FROM private.qa_account_v2_gate
   WHERE id=1 AND enabled) THEN
  RAISE EXCEPTION 'Account purge inventory is not enabled'
    USING ERRCODE='42501';
 END IF;
 IF p_user IS NULL THEN
  RAISE EXCEPTION 'Target user required' USING ERRCODE='22023';
 END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(p_user::text,1));
 SELECT r.purge_after INTO deadline
 FROM public.account_deletion_requests r
 WHERE r.user_id=p_user AND r.cancelled_at IS NULL
   AND r.completed_at IS NULL AND r.purge_after<=now()
   AND r.processing_at IS NULL
 FOR UPDATE;
 IF deadline IS NULL THEN
  RAISE EXCEPTION 'Account is not eligible after its full seven-day grace'
   USING ERRCODE='42501';
 END IF;
 IF NOT EXISTS(SELECT 1 FROM public.user_private_spaces p
   WHERE p.owner_id=p_user) THEN
  RAISE EXCEPTION 'Personal scope missing: halt purge'
   USING ERRCODE='42501';
 END IF;
 INSERT INTO public.qa_account_private_media_purge_queue(
   owner_id,bucket_id,object_path)
 SELECT p_user,o.bucket_id,o.name FROM storage.objects o
 WHERE o.bucket_id IN('onespace-private-note-images',
  'onespace-private-memory-photos','onespace-private-trip-documents',
  'onespace-private-share-in')
 AND o.owner_id=p_user::text
 AND ((
    o.bucket_id='onespace-private-share-in'
    AND split_part(o.name,'/',1)=p_user::text
    AND o.name ~ '^[0-9a-f-]{36}/[0-9a-f-]{36}[.](jpg|jpeg|png|webp|heic|pdf)$'
   ) OR (
    o.bucket_id<>'onespace-private-share-in'
    AND split_part(o.name,'/',2)=p_user::text
    AND o.name ~ '^[0-9a-f-]{36}/[0-9a-f-]{36}/[0-9a-f-]{36}[.](jpg|jpeg|png|webp|m4a|pdf)$'
   ))
 ON CONFLICT DO NOTHING;
 SELECT count(*) INTO queued
 FROM public.qa_account_private_media_purge_queue q
 WHERE q.owner_id=p_user AND q.deleted_at IS NULL;
 SELECT count(*) INTO found_rows
 FROM storage.objects o
 WHERE o.owner_id=p_user::text AND o.bucket_id IN(
 'onespace-private-note-images','onespace-private-memory-photos',
 'onespace-private-trip-documents','onespace-private-share-in');
 IF queued<>found_rows THEN
  RAISE EXCEPTION 'Account private Storage inventory incomplete: no deletion permitted'
   USING ERRCODE='42501';
 END IF;
 RETURN jsonb_build_object('eligible',true,'owner_id',p_user,
   'files_queued',queued,'due_at',deadline,
   'next_step','not_activated; verify Auth foreign keys and physical removal');
END $q$;
REVOKE ALL ON FUNCTION private.qa_inventory_due_private_media(uuid)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION private.qa_inventory_due_private_media(uuid)
 TO service_role;
