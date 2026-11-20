-- Reconciled 2026-11-20: applied to QA (ugwrpeduzyzrujkizqfo) on 2026-11-20 from
-- qa/activities-memories-two-scope-cutover-20261120:supabase/schema/0279_qa_auth_account_owned_root_cascades.sql (original number 0279). Kept verbatim so the
-- repository replays to the live QA schema. QA only; never apply to Production.
-- QA ONLY: account-owned roots already cascade from user_private_spaces,
-- but their second auth.users author FK was NO ACTION. PostgreSQL blocks the
-- Auth deletion before it can cascade the private namespace (verified with a
-- synthetic QA Auth user). Make ONLY these account-owned root author/actor FKs
-- cascade as well. Other shared FK dependencies remain guarded by preflight.
-- Schema-only, no Auth users or content deleted.
DO $m$
DECLARE r record;count_changed integer:=0;
BEGIN
 FOR r IN
  SELECT c.conrelid::regclass::text tab,c.conname,
    a.attname col,pg_get_constraintdef(c.oid) definition
  FROM pg_constraint c JOIN pg_class cl ON cl.oid=c.conrelid
   JOIN pg_namespace ns ON ns.oid=cl.relnamespace
   JOIN pg_attribute a ON a.attrelid=c.conrelid AND a.attnum=c.conkey[1]
  WHERE c.contype='f' AND c.confrelid='auth.users'::regclass
   AND c.confdeltype IN('a','r') AND cardinality(c.conkey)=1
   AND ns.nspname='public'
   AND EXISTS(SELECT 1 FROM pg_constraint private_fk
     WHERE private_fk.conrelid=c.conrelid
       AND private_fk.confrelid='public.user_private_spaces'::regclass
       AND private_fk.confdeltype='c')
  ORDER BY c.conrelid::regclass::text,a.attname
 LOOP
  IF r.definition NOT LIKE
    format('FOREIGN KEY (%I) REFERENCES auth.users(id)%%',r.col) THEN
   RAISE EXCEPTION 'Unexpected auth FK shape % on %',r.definition,r.tab;
  END IF;
  EXECUTE format('ALTER TABLE %s DROP CONSTRAINT %I',r.tab,r.conname);
  EXECUTE format('ALTER TABLE %s ADD CONSTRAINT %I FOREIGN KEY (%I) REFERENCES auth.users(id) ON DELETE CASCADE NOT VALID',
    r.tab,r.conname,r.col);
  count_changed:=count_changed+1;
 END LOOP;
 IF count_changed<>18 THEN
  RAISE EXCEPTION 'Private root auth FK inventory drift: expected 18 changed %',
   count_changed;
 END IF;
END $m$;
