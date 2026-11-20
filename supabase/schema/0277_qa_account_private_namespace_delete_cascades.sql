-- Reconciled 2026-11-20: applied to QA (ugwrpeduzyzrujkizqfo) on 2026-11-20 from
-- qa/activities-memories-two-scope-cutover-20261120:supabase/schema/0270_qa_account_private_namespace_delete_cascades.sql (original number 0270). Kept verbatim so the
-- repository replays to the live QA schema. QA only; never apply to Production.
-- QA ONLY: the account's private namespace and ALL of its direct owners'
-- content have the same lifetime. After an *explicit, due, verified* account
-- deletion, its private rows may cascade; ending the couple NEVER deletes this
-- namespace. This migration changes only FK rules; deletes no data.
-- The finalizer remains fully disabled and cannot be reached by app clients.
DO $q$
DECLARE r record; count_changed integer:=0;
BEGIN
 FOR r IN
 SELECT c.conrelid::regclass::text AS tab,c.conname,
   pg_get_constraintdef(c.oid) AS original_definition
 FROM pg_constraint c
 JOIN pg_class cl ON cl.oid=c.conrelid
 JOIN pg_namespace ns ON ns.oid=cl.relnamespace
 WHERE c.contype='f' AND c.confrelid='public.user_private_spaces'::regclass
   AND ns.nspname='public' AND cardinality(c.conkey)=1
 ORDER BY c.conrelid::regclass::text
 LOOP
  IF r.original_definition NOT LIKE
   'FOREIGN KEY (private_space_id) REFERENCES user_private_spaces(owner_id)%' THEN
    RAISE EXCEPTION 'Unexpected owner-FK definition on %: %',r.tab,r.original_definition;
  END IF;
  IF r.original_definition NOT LIKE '%ON DELETE CASCADE%' THEN
   EXECUTE format('ALTER TABLE %s DROP CONSTRAINT %I',r.tab,r.conname);
   EXECUTE format(
    'ALTER TABLE %s ADD CONSTRAINT %I FOREIGN KEY (private_space_id) REFERENCES public.user_private_spaces(owner_id) ON DELETE CASCADE NOT VALID',
    r.tab,r.conname);
   count_changed:=count_changed+1;
  END IF;
 END LOOP;
 IF count_changed<20 THEN
   RAISE EXCEPTION 'Unexpected private namespace FK inventory (changed %); review before proceeding',
     count_changed;
 END IF;
END $q$;
