-- Reconciled 2026-11-20: applied to QA (ugwrpeduzyzrujkizqfo) on 2026-11-20 from
-- qa/activities-memories-two-scope-cutover-20261120:supabase/schema/0280_qa_account_audit_history_actor_cascade.sql (original number 0280). Kept verbatim so the
-- repository replays to the live QA schema. QA only; never apply to Production.
-- QA: account deletion must remove personally identifying action history.
-- SET NULL actor_id conflicts with the concurrent private-space CASCADE
-- during Auth deletion; delete that user's audit rows instead. Relationship
-- termination still removes shared-scope audit via space_id CASCADE.
ALTER TABLE public.record_action_history
 DROP CONSTRAINT IF EXISTS record_action_history_actor_id_fkey;
ALTER TABLE public.record_action_history
 ADD CONSTRAINT record_action_history_actor_id_fkey
 FOREIGN KEY(actor_id) REFERENCES auth.users(id)
 ON DELETE CASCADE NOT VALID;
