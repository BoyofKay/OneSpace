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
