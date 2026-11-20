-- QA read-only, rollback: discover every public/private FK to auth.users
-- and whether deleting a requesting account would fail under NO ACTION.
-- This is a preflight inventory, NOT an account finalizer. No personal values.
BEGIN;
CREATE TEMP TABLE qa_auth_user_fk_blockers(
 target_table text, target_column text, on_delete text,
 account_reference_count bigint
) ON COMMIT DROP;
DO $q$
DECLARE c record; n bigint;
BEGIN
 FOR c IN
 SELECT co.conrelid::regclass::text AS table_name,
   a.attname AS column_name,
   CASE co.confdeltype WHEN 'c' THEN 'CASCADE'
      WHEN 'n' THEN 'SET NULL' WHEN 'd' THEN 'SET DEFAULT'
      WHEN 'r' THEN 'RESTRICT' ELSE 'NO ACTION' END AS delete_action
 FROM pg_constraint co
 JOIN pg_class child ON child.oid=co.conrelid
 JOIN pg_namespace ns ON ns.oid=child.relnamespace
 JOIN pg_attribute a ON a.attrelid=co.conrelid AND a.attnum=co.conkey[1]
 WHERE co.contype='f' AND co.confrelid='auth.users'::regclass
 AND ns.nspname IN('public','private') AND cardinality(co.conkey)=1
 ORDER BY co.conrelid::regclass::text,a.attname
 LOOP
  EXECUTE format('SELECT count(*) FROM %s WHERE %I IN (SELECT owner_id FROM public.user_private_spaces)',
    c.table_name,c.column_name) INTO n;
  INSERT INTO pg_temp.qa_auth_user_fk_blockers
  VALUES(c.table_name,c.column_name,c.delete_action,n);
 END LOOP;
END $q$;
SELECT on_delete,count(*) relation_count,
 sum(account_reference_count) existing_references,
 count(*) FILTER(WHERE account_reference_count>0) populated_relations
FROM pg_temp.qa_auth_user_fk_blockers
GROUP BY on_delete ORDER BY on_delete;
SELECT target_table,target_column,account_reference_count
FROM pg_temp.qa_auth_user_fk_blockers
WHERE on_delete IN('NO ACTION','RESTRICT') AND account_reference_count>0
ORDER BY target_table,target_column;
ROLLBACK;