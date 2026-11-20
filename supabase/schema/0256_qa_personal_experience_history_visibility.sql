-- QA follow-up: read the account-owned revision history already written by
-- experience_update_audit; old couple-only SELECT policy cannot see it.
DROP POLICY IF EXISTS "QA owner reads personal Experience revisions" ON public.shared_experience_revisions;
CREATE POLICY "QA owner reads personal Experience revisions"
 ON public.shared_experience_revisions FOR SELECT TO authenticated
 USING(EXISTS(SELECT 1 FROM public.shared_experiences e
   WHERE e.id=shared_experience_revisions.experience_id
    AND e.private_space_id=(select auth.uid())
    AND e.created_by=(select auth.uid())
    AND e.space_id IS NULL AND e.visibility='private'));

-- The shared comment logger intentionally returns early on null space_id.
-- Write an account-owned action history for private comments on the same path.
CREATE OR REPLACE FUNCTION private.qa_personal_experience_comment_audit()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $q$
DECLARE owner_id uuid;changed text[];action_name text;
BEGIN
 SELECT e.private_space_id INTO owner_id FROM public.shared_experiences e
 WHERE e.id=new.experience_id AND e.private_space_id IS NOT NULL
 AND e.visibility='private' AND e.space_id IS NULL;
 IF owner_id IS NULL THEN RETURN new;END IF;
 IF tg_op='INSERT' THEN
   changed:=ARRAY['body']; action_name:='created';
 ELSE
   changed:=ARRAY[]::text[];
   IF new.body IS DISTINCT FROM old.body THEN changed:=array_append(changed,'body');END IF;
   IF new.archived_at IS DISTINCT FROM old.archived_at THEN
      changed:=array_append(changed,'archived_at');END IF;
   IF cardinality(changed)=0 THEN RETURN new;END IF;
   action_name:=CASE WHEN old.archived_at IS NULL AND new.archived_at IS NOT NULL
      THEN 'archived'
    WHEN old.archived_at IS NOT NULL AND new.archived_at IS NULL
      THEN 'restored' ELSE 'edited' END;
 END IF;
 INSERT INTO public.record_action_history
   (private_space_id,record_kind,record_id,actor_id,action,changed_fields)
 VALUES(owner_id,'experience_comment',new.id,auth.uid(),action_name,changed);
 RETURN new;
END $q$;
REVOKE ALL ON FUNCTION private.qa_personal_experience_comment_audit()
 FROM public,anon,authenticated;
DROP TRIGGER IF EXISTS qa_experience_private_comment_audit
 ON public.shared_experience_comments;
CREATE TRIGGER qa_experience_private_comment_audit
 AFTER INSERT OR UPDATE OF body,archived_at ON public.shared_experience_comments
 FOR EACH ROW EXECUTE FUNCTION private.qa_personal_experience_comment_audit();
DROP POLICY IF EXISTS "QA personal Experience comment action history" ON public.record_action_history;
CREATE POLICY "QA personal Experience comment action history"
 ON public.record_action_history FOR SELECT TO authenticated
 USING(record_kind='experience_comment' AND private_space_id=(select auth.uid())
  AND EXISTS(SELECT 1 FROM public.shared_experience_comments c
   JOIN public.shared_experiences e ON e.id=c.experience_id
   WHERE c.id=record_id AND c.created_by=(select auth.uid())
    AND e.private_space_id=(select auth.uid())
    AND e.created_by=(select auth.uid())
    AND e.space_id IS NULL AND e.visibility='private'));
