-- Reconciled 2026-11-20: applied to QA (ugwrpeduzyzrujkizqfo) on 2026-11-20 from
-- qa/activities-memories-two-scope-cutover-20261120:supabase/schema/0273_qa_account_private_activity_images_and_voice.sql (original number 0273). Kept verbatim so the
-- repository replays to the live QA schema. QA only; never apply to Production.
-- QA ONLY: personal Activity photos and M4A voice notes are stored in
-- account-owned private buckets, not in the relationship's shared media bucket.
INSERT INTO storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
VALUES
 ('onespace-private-activity-media','onespace-private-activity-media',false,6291456,
   ARRAY['image/jpeg','image/png','image/webp']::text[]),
 ('onespace-private-activity-voice','onespace-private-activity-voice',false,5242880,
   ARRAY['audio/mp4','audio/x-m4a']::text[])
ON CONFLICT(id) DO NOTHING;

ALTER TABLE public.activity_comments ADD COLUMN IF NOT EXISTS voice_bucket_id text
 NOT NULL DEFAULT 'onespace-activity-voice';
ALTER TABLE public.activity_comments DROP CONSTRAINT IF EXISTS qa_activity_voice_bucket_allowlist;
ALTER TABLE public.activity_comments ADD CONSTRAINT qa_activity_voice_bucket_allowlist
 CHECK(voice_bucket_id IN('onespace-activity-voice','onespace-private-activity-voice'))
 NOT VALID;

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
    'location','countdown','image','voice') THEN
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
 FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION private.qa_activity_media_scope_guard()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $q$
DECLARE p record; a_id uuid:=new.activity_id; actor uuid;target_path text;
  desired_bucket text;actual_bucket text;extension text;media_kind text;
BEGIN
 IF current_user NOT IN ('authenticated','anon') THEN RETURN new;END IF;
 SELECT a.space_id,a.private_space_id,a.created_by,a.visibility
 INTO p FROM public.activities a WHERE a.id=a_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'Activity unavailable' USING ERRCODE='42501';END IF;
 IF tg_table_name='activity_components' THEN
  actor:=new.created_by;media_kind:=new.kind;
  IF new.kind NOT IN('image','voice') THEN RETURN new;END IF;
  target_path:=CASE WHEN new.kind='image' THEN new.payload->>'object_path'
   ELSE new.payload->>'voice_path' END;
  desired_bucket:=CASE WHEN new.kind='image'
   THEN 'onespace-private-activity-media' ELSE 'onespace-private-activity-voice' END;
  actual_bucket:=new.payload->>'bucket_id';
  IF tg_op='UPDATE' AND
    (new.kind IS DISTINCT FROM old.kind OR
    (new.payload->>'object_path') IS DISTINCT FROM (old.payload->>'object_path') OR
    (new.payload->>'voice_path') IS DISTINCT FROM (old.payload->>'voice_path') OR
    (new.payload->>'bucket_id') IS DISTINCT FROM (old.payload->>'bucket_id')) THEN
   RAISE EXCEPTION 'Activity media file identity cannot be replaced'
    USING ERRCODE='42501';END IF;
 ELSE
  actor:=new.author_id;media_kind:='voice';
  IF new.voice_path IS NULL THEN RETURN new;END IF;
  target_path:=new.voice_path;
  actual_bucket:=new.voice_bucket_id;
  desired_bucket:='onespace-private-activity-voice';
  IF tg_op='UPDATE' AND
    (new.voice_path IS DISTINCT FROM old.voice_path OR
     new.voice_bucket_id IS DISTINCT FROM old.voice_bucket_id OR
     new.author_id IS DISTINCT FROM old.author_id OR
     new.activity_id IS DISTINCT FROM old.activity_id) THEN
    RAISE EXCEPTION 'Activity voice author and Storage file cannot change'
      USING ERRCODE='42501';END IF;
 END IF;
 IF target_path IS NULL OR target_path NOT LIKE
   (a_id::text||'/'||actor::text||'/%') OR
  target_path !~ '^[0-9a-f-]{36}/[0-9a-f-]{36}/[0-9a-f-]{36}[.](jpg|jpeg|png|webp|m4a)$' THEN
  RAISE EXCEPTION 'Activity attachment path does not match owner and parent'
   USING ERRCODE='42501';
 END IF;
 extension:=split_part(target_path,'.',2);
 IF (media_kind='image' AND extension NOT IN('jpg','jpeg','png','webp'))
  OR (media_kind='voice' AND extension<>'m4a') THEN
  RAISE EXCEPTION 'Activity media type mismatch' USING ERRCODE='42501';END IF;
 IF p.private_space_id IS NOT NULL THEN
  IF p.private_space_id IS DISTINCT FROM auth.uid()
   OR p.created_by IS DISTINCT FROM auth.uid()
   OR actor IS DISTINCT FROM auth.uid()
   OR p.space_id IS NOT NULL OR p.visibility<>'private'
   OR actual_bucket IS DISTINCT FROM desired_bucket THEN
   RAISE EXCEPTION 'Personal media must remain in account bucket'
    USING ERRCODE='42501';END IF;
 ELSE
  IF p.space_id IS NULL OR p.visibility<>'shared'
   OR NOT private.is_space_member(p.space_id)
   OR (SELECT count(*) FROM public.space_members m WHERE m.space_id=p.space_id)<>2
   OR actor IS DISTINCT FROM auth.uid()
   OR actual_bucket IS DISTINCT FROM replace(desired_bucket,'-private-','-') THEN
   -- Legacy shared components may omit their bucket ID entirely.
   IF NOT(tg_table_name='activity_components' AND actual_bucket IS NULL
     AND p.space_id IS NOT NULL AND p.visibility='shared'
     AND private.is_space_member(p.space_id)
     AND (SELECT count(*) FROM public.space_members m WHERE m.space_id=p.space_id)=2
     AND actor=auth.uid()) THEN
     RAISE EXCEPTION 'Shared media requires current couple storage'
      USING ERRCODE='42501';END IF;
  END IF;
 END IF;
 RETURN new;
END $q$;
REVOKE ALL ON FUNCTION private.qa_activity_media_scope_guard()
 FROM PUBLIC,anon,authenticated;
DROP TRIGGER IF EXISTS zzz_qa_activity_component_media_scope ON public.activity_components;
CREATE TRIGGER zzz_qa_activity_component_media_scope BEFORE INSERT OR UPDATE
 ON public.activity_components FOR EACH ROW
 EXECUTE FUNCTION private.qa_activity_media_scope_guard();
DROP TRIGGER IF EXISTS zzz_qa_activity_comment_voice_scope ON public.activity_comments;
CREATE TRIGGER zzz_qa_activity_comment_voice_scope BEFORE INSERT OR UPDATE
 ON public.activity_comments FOR EACH ROW
 EXECUTE FUNCTION private.qa_activity_media_scope_guard();

-- Upload requires exact personal parent ownership, fixed folder shape and MIME.
DROP POLICY IF EXISTS "QA upload account-owned Activity images" ON storage.objects;
CREATE POLICY "QA upload account-owned Activity images" ON storage.objects
 FOR INSERT TO authenticated WITH CHECK(bucket_id='onespace-private-activity-media'
 AND (storage.foldername(name))[2]=(select auth.uid())::text
 AND array_length(storage.foldername(name),1)=2
 AND storage.extension(name) IN('jpg','jpeg','png','webp')
 AND EXISTS(SELECT 1 FROM public.activities a
  WHERE a.id::text=(storage.foldername(name))[1]
   AND a.private_space_id=(select auth.uid()) AND a.created_by=(select auth.uid())
   AND a.space_id IS NULL AND a.visibility='private'));
DROP POLICY IF EXISTS "QA upload account-owned Activity voice" ON storage.objects;
CREATE POLICY "QA upload account-owned Activity voice" ON storage.objects
 FOR INSERT TO authenticated WITH CHECK(bucket_id='onespace-private-activity-voice'
 AND (storage.foldername(name))[2]=(select auth.uid())::text
 AND array_length(storage.foldername(name),1)=2
 AND storage.extension(name)='m4a'
 AND EXISTS(SELECT 1 FROM public.activities a
  WHERE a.id::text=(storage.foldername(name))[1]
   AND a.private_space_id=(select auth.uid()) AND a.created_by=(select auth.uid())
   AND a.space_id IS NULL AND a.visibility='private'));

DROP POLICY IF EXISTS "QA owner reads personal Activity image bytes" ON storage.objects;
CREATE POLICY "QA owner reads personal Activity image bytes" ON storage.objects
 FOR SELECT TO authenticated USING(bucket_id='onespace-private-activity-media'
 AND (storage.foldername(name))[2]=(select auth.uid())::text
 AND EXISTS(SELECT 1 FROM public.activities a
  WHERE a.id::text=(storage.foldername(name))[1]
   AND a.private_space_id=(select auth.uid()) AND a.created_by=(select auth.uid())
   AND a.space_id IS NULL AND a.visibility='private')
 AND (EXISTS(SELECT 1 FROM public.activity_components c
   WHERE c.activity_id::text=(storage.foldername(name))[1]
   AND c.created_by=(select auth.uid()) AND c.kind='image'
   AND c.payload->>'object_path'=storage.objects.name
   AND c.payload->>'bucket_id'='onespace-private-activity-media')
   OR (storage.objects.created_at>now()-interval '10 minutes' AND
      NOT EXISTS(SELECT 1 FROM public.activity_components c
       WHERE c.payload->>'object_path'=storage.objects.name))));
DROP POLICY IF EXISTS "QA owner reads personal Activity voice bytes" ON storage.objects;
CREATE POLICY "QA owner reads personal Activity voice bytes" ON storage.objects
 FOR SELECT TO authenticated USING(bucket_id='onespace-private-activity-voice'
 AND (storage.foldername(name))[2]=(select auth.uid())::text
 AND EXISTS(SELECT 1 FROM public.activities a
  WHERE a.id::text=(storage.foldername(name))[1]
   AND a.private_space_id=(select auth.uid()) AND a.created_by=(select auth.uid())
   AND a.space_id IS NULL AND a.visibility='private')
 AND (EXISTS(SELECT 1 FROM public.activity_components c
   WHERE c.activity_id::text=(storage.foldername(name))[1]
   AND c.created_by=(select auth.uid()) AND c.kind='voice'
   AND c.payload->>'voice_path'=storage.objects.name
   AND c.payload->>'bucket_id'='onespace-private-activity-voice')
  OR EXISTS(SELECT 1 FROM public.activity_comments cm
   WHERE cm.activity_id::text=(storage.foldername(name))[1]
    AND cm.author_id=(select auth.uid()) AND cm.voice_path=storage.objects.name
    AND cm.voice_bucket_id='onespace-private-activity-voice')
  OR (storage.objects.created_at>now()-interval '10 minutes' AND
   NOT EXISTS(SELECT 1 FROM public.activity_components c
    WHERE c.payload->>'voice_path'=storage.objects.name)
   AND NOT EXISTS(SELECT 1 FROM public.activity_comments cm
    WHERE cm.voice_path=storage.objects.name))));

DROP POLICY IF EXISTS "QA cleanup unattached personal Activity image" ON storage.objects;
CREATE POLICY "QA cleanup unattached personal Activity image" ON storage.objects
 FOR DELETE TO authenticated USING(bucket_id='onespace-private-activity-media'
 AND (storage.foldername(name))[2]=(select auth.uid())::text
 AND EXISTS(SELECT 1 FROM public.activities a WHERE a.id::text=(storage.foldername(name))[1]
 AND a.private_space_id=(select auth.uid()) AND a.created_by=(select auth.uid()))
 AND NOT EXISTS(SELECT 1 FROM public.activity_components c
  WHERE c.payload->>'object_path'=storage.objects.name));
DROP POLICY IF EXISTS "QA cleanup unattached personal Activity voice" ON storage.objects;
CREATE POLICY "QA cleanup unattached personal Activity voice" ON storage.objects
 FOR DELETE TO authenticated USING(bucket_id='onespace-private-activity-voice'
 AND (storage.foldername(name))[2]=(select auth.uid())::text
 AND EXISTS(SELECT 1 FROM public.activities a WHERE a.id::text=(storage.foldername(name))[1]
 AND a.private_space_id=(select auth.uid()) AND a.created_by=(select auth.uid()))
 AND NOT EXISTS(SELECT 1 FROM public.activity_components c
  WHERE c.payload->>'voice_path'=storage.objects.name)
 AND NOT EXISTS(SELECT 1 FROM public.activity_comments cm
  WHERE cm.voice_path=storage.objects.name));
