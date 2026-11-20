-- Reconciled 2026-11-20: applied to QA (ugwrpeduzyzrujkizqfo) on 2026-11-20 from
-- qa/activities-memories-two-scope-cutover-20261120:supabase/schema/0259_qa_enable_private_attachment_guard_fix.sql (original number 0259). Kept verbatim so the
-- repository replays to the live QA schema. QA only; never apply to Production.
-- QA: retire provisional private-file denial only after dedicated, exact-scope
-- private Storage buckets and attachment metadata RLS from 0258 are installed.
-- The old restrictive rules were written before personal media existed.
DROP TRIGGER IF EXISTS qa_block_private_memory_photo ON public.memory_photos;
DROP POLICY IF EXISTS "QA personal memories no couple-bucket photo updates" ON public.memory_photos;
DROP POLICY IF EXISTS "QA personal memories no couple-bucket photo writes" ON public.memory_photos;
DROP POLICY IF EXISTS "QA trip_attachments authorized insert" ON public.trip_attachments;
DROP POLICY IF EXISTS "QA trip_attachments authorized update" ON public.trip_attachments;

CREATE OR REPLACE FUNCTION private.qa_trip_child_parent_guard()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $q$
DECLARE parent_scope record;
BEGIN
 IF current_user NOT IN ('authenticated','anon') THEN RETURN NEW;END IF;
 IF tg_op='UPDATE' AND (
   new.trip_id IS DISTINCT FROM old.trip_id OR
   new.created_by IS DISTINCT FROM old.created_by
 ) THEN RAISE EXCEPTION 'Trip child cannot change owner or parent Trip' USING ERRCODE='42501';END IF;
 IF tg_op='INSERT' AND new.created_by IS DISTINCT FROM auth.uid() THEN
  RAISE EXCEPTION 'Trip child author must be signed-in user' USING ERRCODE='42501';
 END IF;
 IF tg_table_name='trip_attachments' THEN
  SELECT space_id,private_space_id,created_by,visibility INTO parent_scope
  FROM public.shared_trips t WHERE t.id=new.trip_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Trip parent unavailable' USING ERRCODE='42501';END IF;
  IF parent_scope.private_space_id IS NOT NULL THEN
    IF parent_scope.private_space_id IS DISTINCT FROM auth.uid()
       OR parent_scope.created_by IS DISTINCT FROM auth.uid()
       OR parent_scope.space_id IS NOT NULL
       OR parent_scope.visibility<>'private'
       OR new.storage_bucket_id<>'onespace-private-trip-documents' THEN
       RAISE EXCEPTION 'Personal attachment must remain in account-owned bucket'
         USING ERRCODE='42501';
    END IF;
  ELSIF parent_scope.space_id IS NULL OR parent_scope.visibility<>'shared'
    OR NOT private.is_space_member(parent_scope.space_id)
    OR (SELECT count(*) FROM public.space_members m WHERE m.space_id=parent_scope.space_id)<>2
    OR new.storage_bucket_id<>'onespace-trip-documents' THEN
       RAISE EXCEPTION 'Couple attachment requires current shared bucket'
        USING ERRCODE='42501';
  END IF;
  IF new.item_id IS NOT NULL AND NOT EXISTS(
    SELECT 1 FROM public.trip_items i WHERE i.id=new.item_id AND i.trip_id=new.trip_id
  ) THEN RAISE EXCEPTION 'Document itinerary belongs to another Trip' USING ERRCODE='42501';END IF;
 END IF;
 RETURN new;
END $q$;
REVOKE ALL ON FUNCTION private.qa_trip_child_parent_guard() FROM public,anon,authenticated;

ALTER TABLE public.memory_photo_revisions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "QA owner reads personal memory-photo revisions" ON public.memory_photo_revisions;
CREATE POLICY "QA owner reads personal memory-photo revisions" ON public.memory_photo_revisions
 FOR SELECT TO authenticated USING(
 EXISTS(SELECT 1 FROM public.memory_photos p
 JOIN public.memories m ON m.id=p.memory_id
 WHERE p.id=memory_photo_revisions.photo_id AND p.created_by=(select auth.uid())
 AND m.private_space_id=(select auth.uid()) AND m.created_by=(select auth.uid())
 AND m.space_id IS NULL AND m.visibility='private'));
DROP POLICY IF EXISTS "QA current pair sees shared memory-photo revisions" ON public.memory_photo_revisions;
CREATE POLICY "QA current pair sees shared memory-photo revisions" ON public.memory_photo_revisions
 FOR SELECT TO authenticated USING(
 EXISTS(SELECT 1 FROM public.memory_photos p
 JOIN public.memories m ON m.id=p.memory_id
 WHERE p.id=memory_photo_revisions.photo_id AND p.storage_bucket_id='onespace-memory-photos'
 AND m.private_space_id IS NULL AND m.visibility='shared'
 AND private.is_space_member(m.space_id)
 AND (SELECT count(*) FROM public.space_members x WHERE x.space_id=m.space_id)=2));
GRANT SELECT ON public.memory_photo_revisions TO authenticated;
