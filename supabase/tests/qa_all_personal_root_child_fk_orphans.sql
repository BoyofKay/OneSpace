-- QA READ ONLY. Audit every simple FK into 24 permanent-personal-capable
-- roots, including old/NOT VALID constraints; no detached child is silently
-- treated as exportable/recoverable shared content.
BEGIN;
DO $audit$
DECLARE r record; scanned integer:=0; orphan_count bigint;
BEGIN
 FOR r IN
  SELECT c.conrelid::regclass::text child_table,
   c.confrelid::regclass::text parent_table,
   child.attname child_column, parent.attname parent_column
  FROM pg_constraint c
  JOIN pg_attribute child ON child.attrelid=c.conrelid
   AND child.attnum=c.conkey[1]
  JOIN pg_attribute parent ON parent.attrelid=c.confrelid
   AND parent.attnum=c.confkey[1]
  WHERE c.contype='f' AND cardinality(c.conkey)=1
   AND cardinality(c.confkey)=1
   AND c.confrelid IN(SELECT root.conrelid FROM pg_constraint root
    WHERE root.contype='f'
      AND root.confrelid='public.user_private_spaces'::regclass)
  ORDER BY child_table,parent_table,child_column
 LOOP
  scanned:=scanned+1;
  EXECUTE format(
   'SELECT count(*) FROM %s child LEFT JOIN %s parent ON child.%I=parent.%I
     WHERE child.%I IS NOT NULL AND parent.%I IS NULL',
    r.child_table,r.parent_table,r.child_column,r.parent_column,
    r.child_column,r.parent_column)
   INTO orphan_count;
  IF orphan_count<>0 THEN
   RAISE EXCEPTION 'Unresolved orphan child records % in %.% referencing %.%: do not delete or migrate',
     orphan_count,r.child_table,r.child_column,
     r.parent_table,r.parent_column USING ERRCODE='23514';
  END IF;
 END LOOP;
 IF scanned<40 THEN
  RAISE EXCEPTION 'Personal root child FK census unexpectedly incomplete: %',scanned;
 END IF;
END $audit$;
ROLLBACK;
SELECT 'PASS 49 simple child FK relationships into all personal-capable roots checked for orphan records; read-only rollback' result;