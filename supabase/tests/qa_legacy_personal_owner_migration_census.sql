-- QA-only read-only census before any ownership migration.
-- Counts only; never lists user IDs, note bodies, emails, private text or media paths.
-- Uses a temporary table and rolls back. Identifies owners and pair edges that
-- require author/child preservation before enabling irreversible deletion.
BEGIN;
CREATE TEMP TABLE qa_private_census(
  root_table text PRIMARY KEY, legacy_private bigint NOT NULL,
  account_private bigint NOT NULL, shared_current_pair bigint NOT NULL,
  shared_unpaired_or_stale bigint NOT NULL, private_wrong_owner bigint NOT NULL,
  other_scope bigint NOT NULL
) ON COMMIT DROP;
DO $q$
DECLARE r record;
BEGIN
 FOR r IN
 SELECT c.table_name
 FROM information_schema.columns c
 WHERE c.table_schema='public'
 GROUP BY c.table_name
 HAVING bool_or(c.column_name='space_id')
    AND bool_or(c.column_name='private_space_id')
    AND bool_or(c.column_name='created_by')
    AND bool_or(c.column_name='visibility')
 LOOP
  EXECUTE format($f$
   INSERT INTO pg_temp.qa_private_census
    (root_table,legacy_private,account_private,shared_current_pair,
     shared_unpaired_or_stale,private_wrong_owner,other_scope)
   SELECT %L,
    count(*) FILTER (WHERE t.space_id IS NOT NULL
      AND t.private_space_id IS NULL AND t.visibility='private'),
    count(*) FILTER (WHERE t.private_space_id IS NOT NULL AND t.space_id IS NULL
      AND t.visibility='private' AND t.created_by=t.private_space_id),
    count(*) FILTER (WHERE t.space_id IS NOT NULL AND t.private_space_id IS NULL
      AND t.visibility='shared' AND (SELECT count(*) FROM public.space_members m
       WHERE m.space_id=t.space_id)=2),
    count(*) FILTER (WHERE t.space_id IS NOT NULL AND t.private_space_id IS NULL
      AND t.visibility='shared' AND (SELECT count(*) FROM public.space_members m
       WHERE m.space_id=t.space_id)<>2),
    count(*) FILTER (WHERE t.private_space_id IS NOT NULL
      AND (t.created_by IS DISTINCT FROM t.private_space_id OR
       t.space_id IS NOT NULL OR t.visibility<>'private')),
    count(*) FILTER (WHERE NOT (
      (t.space_id IS NOT NULL AND t.private_space_id IS NULL AND
       t.visibility IN ('shared','private'))
      OR (t.space_id IS NULL AND t.private_space_id IS NOT NULL AND
       t.visibility='private')))
   FROM public.%I t
   $f$,r.table_name,r.table_name);
 END LOOP;
END $q$;
SELECT root_table,legacy_private,account_private,shared_current_pair,
 shared_unpaired_or_stale,private_wrong_owner,other_scope
FROM pg_temp.qa_private_census ORDER BY root_table;
ROLLBACK;