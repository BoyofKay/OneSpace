-- QA ONLY. Once an account has requested deletion, do not let it create
-- a new relationship or accept an invitation while pending. Cancellation
-- restores pairing eligibility. Protects finalizer against late re-pair.
-- Backend deletion remains gate-OFF and request_account_deletion is revoked.
CREATE OR REPLACE FUNCTION private.qa_account_pending_delete(p_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $q$
 SELECT p_id IS NOT NULL AND EXISTS(
  SELECT 1 FROM public.account_deletion_requests r
  WHERE r.user_id=p_id AND r.cancelled_at IS NULL AND r.completed_at IS NULL
 );
$q$;
REVOKE ALL ON FUNCTION private.qa_account_pending_delete(uuid)
 FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION private.qa_pending_account_pairing_guard()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $q$
DECLARE owner_id uuid;pair_id uuid;candidate uuid;
BEGIN
 IF tg_table_name='spaces' THEN
  IF private.qa_account_pending_delete(new.created_by) THEN
   RAISE EXCEPTION 'Account pending deletion cannot create a new space'
    USING ERRCODE='42501';END IF;
  RETURN new;
 END IF;
 pair_id:=new.space_id;
 IF tg_table_name='space_members' THEN
  candidate:=new.user_id;
 ELSIF tg_table_name='space_invitations' THEN
  candidate:=new.invited_by;
  IF new.accepted_by IS NOT NULL
   AND private.qa_account_pending_delete(new.accepted_by) THEN
   RAISE EXCEPTION 'Account pending deletion cannot accept a partnership'
    USING ERRCODE='42501';END IF;
 END IF;
 IF private.qa_account_pending_delete(candidate) THEN
  RAISE EXCEPTION 'Account pending deletion cannot start or join a partnership'
   USING ERRCODE='42501';END IF;
 SELECT created_by INTO owner_id FROM public.spaces WHERE id=pair_id;
 IF private.qa_account_pending_delete(owner_id)
  OR EXISTS(SELECT 1 FROM public.space_members m
    WHERE m.space_id=pair_id AND private.qa_account_pending_delete(m.user_id))
 THEN
  RAISE EXCEPTION 'The space has a member pending account deletion'
   USING ERRCODE='42501';
 END IF;
 RETURN new;
END $q$;
REVOKE ALL ON FUNCTION private.qa_pending_account_pairing_guard()
 FROM PUBLIC,anon,authenticated;

DROP TRIGGER IF EXISTS qa_pending_account_blocks_new_space ON public.spaces;
CREATE TRIGGER qa_pending_account_blocks_new_space
 BEFORE INSERT OR UPDATE OF created_by ON public.spaces
 FOR EACH ROW EXECUTE FUNCTION private.qa_pending_account_pairing_guard();

DROP TRIGGER IF EXISTS qa_pending_account_blocks_new_members ON public.space_members;
CREATE TRIGGER qa_pending_account_blocks_new_members
 BEFORE INSERT OR UPDATE OF user_id,space_id ON public.space_members
 FOR EACH ROW EXECUTE FUNCTION private.qa_pending_account_pairing_guard();

DROP TRIGGER IF EXISTS qa_pending_account_blocks_new_invites ON public.space_invitations;
CREATE TRIGGER qa_pending_account_blocks_new_invites
 BEFORE INSERT OR UPDATE OF space_id,invited_by,accepted_by ON public.space_invitations
 FOR EACH ROW EXECUTE FUNCTION private.qa_pending_account_pairing_guard();
