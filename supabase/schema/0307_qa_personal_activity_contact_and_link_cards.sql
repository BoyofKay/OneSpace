-- QA 0307: personal Activities may hold Contact information and Link cards.
--
-- Before: the personal-child guard (0280) refused 'contact' and 'link', but the
-- app offers both on every Activity, so adding a contact or a website to a
-- personal Activity failed with "This personal Activity component is
-- unsupported". Both are plain text in the component payload: no Storage
-- object and no reference to another record, so they follow the parent
-- Activity's owner-only access like a note does. Everything else is unchanged.
-- QA only; never apply to Production.

CREATE OR REPLACE FUNCTION private.qa_personal_activity_child_guard()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $q$
DECLARE p record; a_id uuid:=(to_jsonb(new)->>'activity_id')::uuid;
 me uuid:=auth.uid();component uuid;
BEGIN
 SELECT a.space_id,a.private_space_id,a.created_by,a.visibility
 INTO p FROM public.activities a WHERE a.id=a_id;
 IF NOT FOUND OR p.private_space_id IS NULL THEN RETURN new;END IF;
 IF me IS NULL OR p.private_space_id IS DISTINCT FROM me
   OR p.created_by IS DISTINCT FROM me
   OR p.space_id IS NOT NULL OR p.visibility<>'private' THEN
   RAISE EXCEPTION 'Only the account owner may edit personal Activity children'
     USING ERRCODE='42501';
 END IF;
 IF tg_table_name='activity_components' THEN
  IF new.created_by IS DISTINCT FROM me OR new.kind NOT IN
   ('note','option','step','date','price','spec','reminder','tag',
    'location','countdown','image','voice','contact','link') THEN
   RAISE EXCEPTION 'This personal Activity component is unsupported'
    USING ERRCODE='42501';
  END IF;
  component:=new.parent_component_id;
 ELSIF tg_table_name='activity_comments' THEN
  IF new.author_id IS DISTINCT FROM me OR
    (new.voice_path IS NOT NULL AND
     (new.voice_bucket_id<>'onespace-private-activity-voice'
      OR new.voice_seconds IS NULL)) THEN
   RAISE EXCEPTION 'Personal Activity voice must be account-owned'
    USING ERRCODE='42501';
  END IF;
  component:=new.component_id;
  IF new.reply_to IS NOT NULL AND NOT EXISTS(
    SELECT 1 FROM public.activity_comments c
    WHERE c.id=new.reply_to AND c.activity_id=a_id) THEN
    RAISE EXCEPTION 'Reply must belong to this Activity' USING ERRCODE='42501';
  END IF;
 END IF;
 IF component IS NOT NULL AND NOT EXISTS(
   SELECT 1 FROM public.activity_components c
   WHERE c.id=component AND c.activity_id=a_id) THEN
   RAISE EXCEPTION 'Component parent belongs to another Activity'
    USING ERRCODE='42501';
 END IF;
 RETURN new;
END $q$;
REVOKE ALL ON FUNCTION private.qa_personal_activity_child_guard()
 FROM public,anon,authenticated;
