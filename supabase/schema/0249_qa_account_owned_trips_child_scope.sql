-- QA ONLY: account-owned Trips and parent-scoped itinerary, flights, messages, revisions.
-- Do not migrate or remove existing content here. Legacy data migration is separate.
-- Account-owned trip documents are not writable until private Storage is certified.
ALTER TABLE public.shared_trips ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "QA personal trips read" ON public.shared_trips;
CREATE POLICY "QA personal trips read" ON public.shared_trips FOR SELECT TO authenticated
USING (private_space_id=(select auth.uid()) and created_by=(select auth.uid())
  and space_id is null and visibility='private');

DROP POLICY IF EXISTS "QA personal trips create" ON public.shared_trips;
CREATE POLICY "QA personal trips create" ON public.shared_trips FOR INSERT TO authenticated
WITH CHECK (private_space_id=(select auth.uid()) and created_by=(select auth.uid())
  and space_id is null and visibility='private');

DROP POLICY IF EXISTS "QA personal trips edit" ON public.shared_trips;
CREATE POLICY "QA personal trips edit" ON public.shared_trips FOR UPDATE TO authenticated
USING (private_space_id=(select auth.uid()) and created_by=(select auth.uid())
  and space_id is null and visibility='private')
WITH CHECK (private_space_id=(select auth.uid()) and created_by=(select auth.uid())
  and space_id is null and visibility='private');

DROP POLICY IF EXISTS "QA valid trip read scope" ON public.shared_trips;
CREATE POLICY "QA valid trip read scope" ON public.shared_trips AS RESTRICTIVE
FOR SELECT TO authenticated USING(
 (private_space_id=(select auth.uid()) and space_id is null
   and created_by=(select auth.uid()) and visibility='private')
 OR
 (private_space_id is null and space_id is not null and visibility='shared'
   and private.is_space_member(space_id)
   and (select count(*) from public.space_members sm where sm.space_id=shared_trips.space_id)=2)
);

DROP POLICY IF EXISTS "QA trip insert shared only in live pair" ON public.shared_trips;
CREATE POLICY "QA trip insert shared only in live pair" ON public.shared_trips AS RESTRICTIVE
FOR INSERT TO authenticated WITH CHECK(
 (private_space_id=(select auth.uid()) and space_id is null
   and created_by=(select auth.uid()) and visibility='private')
 OR
 (private_space_id is null and space_id is not null and visibility='shared'
   and created_by=(select auth.uid()) and private.is_space_member(space_id)
   and (select count(*) from public.space_members sm where sm.space_id=shared_trips.space_id)=2)
);
DROP POLICY IF EXISTS "QA trip update valid scope" ON public.shared_trips;
CREATE POLICY "QA trip update valid scope" ON public.shared_trips AS RESTRICTIVE
FOR UPDATE TO authenticated USING(
 (private_space_id=(select auth.uid()) and created_by=(select auth.uid())
    and space_id is null and visibility='private')
 OR
 (private_space_id is null and visibility='shared'
    and space_id is not null and private.is_space_member(space_id)
    and (select count(*) from public.space_members sm where sm.space_id=shared_trips.space_id)=2))
WITH CHECK (
 (private_space_id=(select auth.uid()) and created_by=(select auth.uid())
    and space_id is null and visibility='private')
 OR
 (private_space_id is null and visibility='shared'
    and space_id is not null and private.is_space_member(space_id)
    and (select count(*) from public.space_members sm where sm.space_id=shared_trips.space_id)=2)
);

CREATE OR REPLACE FUNCTION private.qa_trip_ownership_guard()
RETURNS trigger LANGUAGE plpgsql SET search_path='' AS $q$
BEGIN
 IF current_user NOT IN ('authenticated','anon') THEN RETURN NEW; END IF;
 IF tg_op='UPDATE' AND (
   old.space_id IS DISTINCT FROM new.space_id OR
   old.private_space_id IS DISTINCT FROM new.private_space_id OR
   old.created_by IS DISTINCT FROM new.created_by OR
   old.visibility IS DISTINCT FROM new.visibility) THEN
   RAISE EXCEPTION 'Trip ownership and privacy cannot be changed in place' USING ERRCODE='42501';
 END IF;
 IF new.private_space_id IS NOT NULL AND
   (new.private_space_id IS DISTINCT FROM auth.uid()
    OR new.created_by IS DISTINCT FROM auth.uid()
    OR new.visibility<>'private' OR new.space_id IS NOT NULL
    OR (new.traveler_id IS NOT NULL AND new.traveler_id IS DISTINCT FROM auth.uid())) THEN
   RAISE EXCEPTION 'Personal trip belongs exclusively to the account owner' USING ERRCODE='42501';
 END IF;
 IF new.visibility='private' AND (new.private_space_id IS DISTINCT FROM auth.uid()
    OR new.space_id IS NOT NULL) THEN
   RAISE EXCEPTION 'Update OneSpace to save personal Trips in your account' USING ERRCODE='42501';
 END IF;
 IF new.visibility='shared' AND (new.space_id IS NULL OR new.private_space_id IS NOT NULL) THEN
   RAISE EXCEPTION 'A shared Trip requires an active couple' USING ERRCODE='42501';
 END IF;
 RETURN NEW;
END $q$;
REVOKE ALL ON FUNCTION private.qa_trip_ownership_guard() FROM public,anon,authenticated;
DROP TRIGGER IF EXISTS zzz_qa_trip_ownership_guard ON public.shared_trips;
CREATE TRIGGER zzz_qa_trip_ownership_guard BEFORE INSERT OR UPDATE ON public.shared_trips
FOR EACH ROW EXECUTE FUNCTION private.qa_trip_ownership_guard();

-- All children inherit parent RLS; immutable foreign keys prevent reparenting.
-- For personal trips, only the owner can add or edit child rows.
-- For a current paired trip, either member can collaborate.

ALTER TABLE public.trip_items ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "QA trip_items parent visibility" ON public.trip_items;
CREATE POLICY "QA trip_items parent visibility" ON public.trip_items
AS RESTRICTIVE FOR SELECT TO authenticated USING(
 EXISTS (SELECT 1 FROM public.shared_trips parent WHERE parent.id=trip_items.trip_id
  AND ((parent.private_space_id=(select auth.uid()) AND parent.created_by=(select auth.uid())
        AND parent.visibility='private' AND parent.space_id IS NULL)
    OR (parent.private_space_id IS NULL AND parent.visibility='shared'
        AND private.is_space_member(parent.space_id)
        AND (SELECT count(*) FROM public.space_members x WHERE x.space_id=parent.space_id)=2)))
);
DROP POLICY IF EXISTS "QA trip_items authorized insert" ON public.trip_items;
CREATE POLICY "QA trip_items authorized insert" ON public.trip_items
AS RESTRICTIVE FOR INSERT TO authenticated WITH CHECK(
 created_by=(select auth.uid()) AND
 EXISTS (SELECT 1 FROM public.shared_trips parent WHERE parent.id=trip_items.trip_id
  AND ((parent.private_space_id=(select auth.uid()) AND parent.created_by=(select auth.uid())
       AND parent.visibility='private' AND parent.space_id IS NULL)
   OR (parent.private_space_id IS NULL AND parent.visibility='shared'
       AND private.is_space_member(parent.space_id)
       AND (SELECT count(*) FROM public.space_members x WHERE x.space_id=parent.space_id)=2)))
 
);
DROP POLICY IF EXISTS "QA trip_items authorized update" ON public.trip_items;
CREATE POLICY "QA trip_items authorized update" ON public.trip_items
AS RESTRICTIVE FOR UPDATE TO authenticated USING(
 EXISTS (SELECT 1 FROM public.shared_trips parent WHERE parent.id=trip_items.trip_id
  AND ((parent.private_space_id=(select auth.uid()) AND parent.created_by=(select auth.uid())
        AND parent.visibility='private' AND parent.space_id IS NULL)
   OR (parent.private_space_id IS NULL AND parent.visibility='shared'
        AND private.is_space_member(parent.space_id)
        AND (SELECT count(*) FROM public.space_members x WHERE x.space_id=parent.space_id)=2)))
 
 
) WITH CHECK(
 EXISTS (SELECT 1 FROM public.shared_trips parent WHERE parent.id=trip_items.trip_id
  AND ((parent.private_space_id=(select auth.uid()) AND parent.created_by=(select auth.uid())
        AND parent.visibility='private' AND parent.space_id IS NULL)
   OR (parent.private_space_id IS NULL AND parent.visibility='shared'
        AND private.is_space_member(parent.space_id)
        AND (SELECT count(*) FROM public.space_members x WHERE x.space_id=parent.space_id)=2)))
 
 
);

ALTER TABLE public.trip_flight_options ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "QA trip_flight_options parent visibility" ON public.trip_flight_options;
CREATE POLICY "QA trip_flight_options parent visibility" ON public.trip_flight_options
AS RESTRICTIVE FOR SELECT TO authenticated USING(
 EXISTS (SELECT 1 FROM public.shared_trips parent WHERE parent.id=trip_flight_options.trip_id
  AND ((parent.private_space_id=(select auth.uid()) AND parent.created_by=(select auth.uid())
        AND parent.visibility='private' AND parent.space_id IS NULL)
    OR (parent.private_space_id IS NULL AND parent.visibility='shared'
        AND private.is_space_member(parent.space_id)
        AND (SELECT count(*) FROM public.space_members x WHERE x.space_id=parent.space_id)=2)))
);
DROP POLICY IF EXISTS "QA trip_flight_options authorized insert" ON public.trip_flight_options;
CREATE POLICY "QA trip_flight_options authorized insert" ON public.trip_flight_options
AS RESTRICTIVE FOR INSERT TO authenticated WITH CHECK(
 created_by=(select auth.uid()) AND
 EXISTS (SELECT 1 FROM public.shared_trips parent WHERE parent.id=trip_flight_options.trip_id
  AND ((parent.private_space_id=(select auth.uid()) AND parent.created_by=(select auth.uid())
       AND parent.visibility='private' AND parent.space_id IS NULL)
   OR (parent.private_space_id IS NULL AND parent.visibility='shared'
       AND private.is_space_member(parent.space_id)
       AND (SELECT count(*) FROM public.space_members x WHERE x.space_id=parent.space_id)=2)))
 
);
DROP POLICY IF EXISTS "QA trip_flight_options authorized update" ON public.trip_flight_options;
CREATE POLICY "QA trip_flight_options authorized update" ON public.trip_flight_options
AS RESTRICTIVE FOR UPDATE TO authenticated USING(
 EXISTS (SELECT 1 FROM public.shared_trips parent WHERE parent.id=trip_flight_options.trip_id
  AND ((parent.private_space_id=(select auth.uid()) AND parent.created_by=(select auth.uid())
        AND parent.visibility='private' AND parent.space_id IS NULL)
   OR (parent.private_space_id IS NULL AND parent.visibility='shared'
        AND private.is_space_member(parent.space_id)
        AND (SELECT count(*) FROM public.space_members x WHERE x.space_id=parent.space_id)=2)))
 
 
) WITH CHECK(
 EXISTS (SELECT 1 FROM public.shared_trips parent WHERE parent.id=trip_flight_options.trip_id
  AND ((parent.private_space_id=(select auth.uid()) AND parent.created_by=(select auth.uid())
        AND parent.visibility='private' AND parent.space_id IS NULL)
   OR (parent.private_space_id IS NULL AND parent.visibility='shared'
        AND private.is_space_member(parent.space_id)
        AND (SELECT count(*) FROM public.space_members x WHERE x.space_id=parent.space_id)=2)))
 
 
);

ALTER TABLE public.trip_messages ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "QA trip_messages parent visibility" ON public.trip_messages;
CREATE POLICY "QA trip_messages parent visibility" ON public.trip_messages
AS RESTRICTIVE FOR SELECT TO authenticated USING(
 EXISTS (SELECT 1 FROM public.shared_trips parent WHERE parent.id=trip_messages.trip_id
  AND ((parent.private_space_id=(select auth.uid()) AND parent.created_by=(select auth.uid())
        AND parent.visibility='private' AND parent.space_id IS NULL)
    OR (parent.private_space_id IS NULL AND parent.visibility='shared'
        AND private.is_space_member(parent.space_id)
        AND (SELECT count(*) FROM public.space_members x WHERE x.space_id=parent.space_id)=2)))
);
DROP POLICY IF EXISTS "QA trip_messages authorized insert" ON public.trip_messages;
CREATE POLICY "QA trip_messages authorized insert" ON public.trip_messages
AS RESTRICTIVE FOR INSERT TO authenticated WITH CHECK(
 created_by=(select auth.uid()) AND
 EXISTS (SELECT 1 FROM public.shared_trips parent WHERE parent.id=trip_messages.trip_id
  AND ((parent.private_space_id=(select auth.uid()) AND parent.created_by=(select auth.uid())
       AND parent.visibility='private' AND parent.space_id IS NULL)
   OR (parent.private_space_id IS NULL AND parent.visibility='shared'
       AND private.is_space_member(parent.space_id)
       AND (SELECT count(*) FROM public.space_members x WHERE x.space_id=parent.space_id)=2)))
 
);
DROP POLICY IF EXISTS "QA trip_messages authorized update" ON public.trip_messages;
CREATE POLICY "QA trip_messages authorized update" ON public.trip_messages
AS RESTRICTIVE FOR UPDATE TO authenticated USING(
 EXISTS (SELECT 1 FROM public.shared_trips parent WHERE parent.id=trip_messages.trip_id
  AND ((parent.private_space_id=(select auth.uid()) AND parent.created_by=(select auth.uid())
        AND parent.visibility='private' AND parent.space_id IS NULL)
   OR (parent.private_space_id IS NULL AND parent.visibility='shared'
        AND private.is_space_member(parent.space_id)
        AND (SELECT count(*) FROM public.space_members x WHERE x.space_id=parent.space_id)=2)))
 AND created_by=(select auth.uid())
 
) WITH CHECK(
 EXISTS (SELECT 1 FROM public.shared_trips parent WHERE parent.id=trip_messages.trip_id
  AND ((parent.private_space_id=(select auth.uid()) AND parent.created_by=(select auth.uid())
        AND parent.visibility='private' AND parent.space_id IS NULL)
   OR (parent.private_space_id IS NULL AND parent.visibility='shared'
        AND private.is_space_member(parent.space_id)
        AND (SELECT count(*) FROM public.space_members x WHERE x.space_id=parent.space_id)=2)))
 AND created_by=(select auth.uid())
 
);

ALTER TABLE public.trip_attachments ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "QA trip_attachments parent visibility" ON public.trip_attachments;
CREATE POLICY "QA trip_attachments parent visibility" ON public.trip_attachments
AS RESTRICTIVE FOR SELECT TO authenticated USING(
 EXISTS (SELECT 1 FROM public.shared_trips parent WHERE parent.id=trip_attachments.trip_id
  AND ((parent.private_space_id=(select auth.uid()) AND parent.created_by=(select auth.uid())
        AND parent.visibility='private' AND parent.space_id IS NULL)
    OR (parent.private_space_id IS NULL AND parent.visibility='shared'
        AND private.is_space_member(parent.space_id)
        AND (SELECT count(*) FROM public.space_members x WHERE x.space_id=parent.space_id)=2)))
);
DROP POLICY IF EXISTS "QA trip_attachments authorized insert" ON public.trip_attachments;
CREATE POLICY "QA trip_attachments authorized insert" ON public.trip_attachments
AS RESTRICTIVE FOR INSERT TO authenticated WITH CHECK(
 created_by=(select auth.uid()) AND
 EXISTS (SELECT 1 FROM public.shared_trips parent WHERE parent.id=trip_attachments.trip_id
  AND ((parent.private_space_id=(select auth.uid()) AND parent.created_by=(select auth.uid())
       AND parent.visibility='private' AND parent.space_id IS NULL)
   OR (parent.private_space_id IS NULL AND parent.visibility='shared'
       AND private.is_space_member(parent.space_id)
       AND (SELECT count(*) FROM public.space_members x WHERE x.space_id=parent.space_id)=2)))
 AND EXISTS (SELECT 1 FROM public.shared_trips t WHERE t.id=trip_attachments.trip_id AND t.visibility='shared' AND t.private_space_id IS NULL AND (trip_attachments.item_id IS NULL OR EXISTS(SELECT 1 FROM public.trip_items i WHERE i.id=trip_attachments.item_id AND i.trip_id=trip_attachments.trip_id)))
);
DROP POLICY IF EXISTS "QA trip_attachments authorized update" ON public.trip_attachments;
CREATE POLICY "QA trip_attachments authorized update" ON public.trip_attachments
AS RESTRICTIVE FOR UPDATE TO authenticated USING(
 EXISTS (SELECT 1 FROM public.shared_trips parent WHERE parent.id=trip_attachments.trip_id
  AND ((parent.private_space_id=(select auth.uid()) AND parent.created_by=(select auth.uid())
        AND parent.visibility='private' AND parent.space_id IS NULL)
   OR (parent.private_space_id IS NULL AND parent.visibility='shared'
        AND private.is_space_member(parent.space_id)
        AND (SELECT count(*) FROM public.space_members x WHERE x.space_id=parent.space_id)=2)))
 
 AND EXISTS(SELECT 1 FROM public.shared_trips t WHERE t.id=trip_attachments.trip_id AND t.visibility='shared' AND t.private_space_id IS NULL)
) WITH CHECK(
 EXISTS (SELECT 1 FROM public.shared_trips parent WHERE parent.id=trip_attachments.trip_id
  AND ((parent.private_space_id=(select auth.uid()) AND parent.created_by=(select auth.uid())
        AND parent.visibility='private' AND parent.space_id IS NULL)
   OR (parent.private_space_id IS NULL AND parent.visibility='shared'
        AND private.is_space_member(parent.space_id)
        AND (SELECT count(*) FROM public.space_members x WHERE x.space_id=parent.space_id)=2)))
 
 AND EXISTS (SELECT 1 FROM public.shared_trips t WHERE t.id=trip_attachments.trip_id AND t.visibility='shared' AND t.private_space_id IS NULL AND (trip_attachments.item_id IS NULL OR EXISTS(SELECT 1 FROM public.trip_items i WHERE i.id=trip_attachments.item_id AND i.trip_id=trip_attachments.trip_id)))
);

ALTER TABLE public.trip_revisions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "QA trip_revisions parent visibility" ON public.trip_revisions;
CREATE POLICY "QA trip_revisions parent visibility" ON public.trip_revisions
AS RESTRICTIVE FOR SELECT TO authenticated USING(
 EXISTS (SELECT 1 FROM public.shared_trips parent WHERE parent.id=trip_revisions.trip_id
  AND ((parent.private_space_id=(select auth.uid()) AND parent.created_by=(select auth.uid())
        AND parent.visibility='private' AND parent.space_id IS NULL)
    OR (parent.private_space_id IS NULL AND parent.visibility='shared'
        AND private.is_space_member(parent.space_id)
        AND (SELECT count(*) FROM public.space_members x WHERE x.space_id=parent.space_id)=2)))
);

CREATE OR REPLACE FUNCTION private.qa_trip_child_parent_guard()
RETURNS trigger LANGUAGE plpgsql SET search_path='' AS $q$
BEGIN
 IF current_user NOT IN ('authenticated','anon') THEN RETURN NEW; END IF;
 IF tg_op='UPDATE' AND (
    new.trip_id IS DISTINCT FROM old.trip_id OR
    new.created_by IS DISTINCT FROM old.created_by) THEN
   RAISE EXCEPTION 'Trip child cannot change owner or parent Trip' USING ERRCODE='42501';
 END IF;
 IF new.created_by IS DISTINCT FROM auth.uid() AND tg_op='INSERT' THEN
   RAISE EXCEPTION 'Trip child author must be signed-in user' USING ERRCODE='42501';
 END IF;
 IF tg_table_name='trip_attachments' THEN
   IF NOT EXISTS(SELECT 1 FROM public.shared_trips tr
      WHERE tr.id=new.trip_id AND tr.visibility='shared'
        AND tr.private_space_id IS NULL AND private.is_space_member(tr.space_id)) THEN
     RAISE EXCEPTION 'Personal trip file storage is not enabled' USING ERRCODE='42501';
   END IF;
   IF new.item_id IS NOT NULL AND NOT EXISTS(
       SELECT 1 FROM public.trip_items i WHERE i.id=new.item_id AND i.trip_id=new.trip_id) THEN
     RAISE EXCEPTION 'Document itinerary item belongs to another Trip' USING ERRCODE='42501';
   END IF;
 END IF;
 RETURN NEW;
END $q$;
REVOKE ALL ON FUNCTION private.qa_trip_child_parent_guard() FROM public,anon,authenticated;
DROP TRIGGER IF EXISTS zzz_qa_trip_child_guard ON public.trip_items;
CREATE TRIGGER zzz_qa_trip_child_guard BEFORE INSERT OR UPDATE ON public.trip_items
FOR EACH ROW EXECUTE FUNCTION private.qa_trip_child_parent_guard();
DROP TRIGGER IF EXISTS zzz_qa_trip_child_guard ON public.trip_flight_options;
CREATE TRIGGER zzz_qa_trip_child_guard BEFORE INSERT OR UPDATE ON public.trip_flight_options
FOR EACH ROW EXECUTE FUNCTION private.qa_trip_child_parent_guard();
DROP TRIGGER IF EXISTS zzz_qa_trip_child_guard ON public.trip_messages;
CREATE TRIGGER zzz_qa_trip_child_guard BEFORE INSERT OR UPDATE ON public.trip_messages
FOR EACH ROW EXECUTE FUNCTION private.qa_trip_child_parent_guard();
DROP TRIGGER IF EXISTS zzz_qa_trip_child_guard ON public.trip_attachments;
CREATE TRIGGER zzz_qa_trip_child_guard BEFORE INSERT OR UPDATE ON public.trip_attachments
FOR EACH ROW EXECUTE FUNCTION private.qa_trip_child_parent_guard();

DROP POLICY IF EXISTS "QA owner reads account Trip action history" ON public.record_action_history;
CREATE POLICY "QA owner reads account Trip action history" ON public.record_action_history
 FOR SELECT TO authenticated USING(record_kind='trip'
 AND private_space_id=(select auth.uid())
 AND EXISTS(SELECT 1 FROM public.shared_trips t WHERE t.id=record_id
   AND t.private_space_id=(select auth.uid()) AND t.created_by=(select auth.uid())
   AND t.visibility='private' AND t.space_id IS NULL));

GRANT SELECT,INSERT,UPDATE ON public.shared_trips TO authenticated;
GRANT SELECT,INSERT,UPDATE ON public.trip_items,public.trip_messages,public.trip_flight_options,public.trip_attachments TO authenticated;
GRANT SELECT ON public.trip_revisions TO authenticated;
