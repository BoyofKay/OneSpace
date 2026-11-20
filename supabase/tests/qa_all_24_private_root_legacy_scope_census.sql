-- QA READ ONLY. Inspect ALL 24 account-private root tables for actual
-- legacy solo, stale couple-private, mixed scope and wrong owner records.
-- This test does not move, archive, clean or delete ANY data.
BEGIN;
DO $scan$
DECLARE r record; n bigint; total_tables int:=0;
 privacy_test text; author_test text; stmt text;
BEGIN
 FOR r IN
  SELECT c.conrelid::regclass tab,
   EXISTS(SELECT 1 FROM pg_attribute a WHERE a.attrelid=c.conrelid
    AND a.attname='visibility' AND NOT a.attisdropped) has_visibility,
   EXISTS(SELECT 1 FROM pg_attribute a WHERE a.attrelid=c.conrelid
    AND a.attname='created_by' AND NOT a.attisdropped) has_creator
  FROM pg_constraint c
  WHERE c.contype='f' AND c.confrelid='public.user_private_spaces'::regclass
  ORDER BY c.conrelid::regclass::text
 LOOP
  total_tables:=total_tables+1;
  privacy_test:=CASE WHEN r.has_visibility THEN
    ' OR (t.private_space_id IS NOT NULL AND t.visibility<>''private'')'
     ||' OR (t.space_id IS NOT NULL AND t.visibility=''private'')'
    ELSE '' END;
  author_test:=CASE WHEN r.has_creator THEN
    ' OR (t.private_space_id IS NOT NULL AND t.created_by IS DISTINCT FROM t.private_space_id)'
    ELSE '' END;
  stmt:=format('SELECT count(*) FROM %s t LEFT JOIN public.spaces s ON s.id=t.space_id
    WHERE (t.space_id IS NULL AND t.private_space_id IS NULL)
      OR (t.space_id IS NOT NULL AND t.private_space_id IS NOT NULL)
      OR (t.space_id IS NOT NULL AND s.personal_owner IS NOT NULL)
      %s %s',
      r.tab,privacy_test,author_test);
  EXECUTE stmt INTO n;
  IF n>0 THEN
   RAISE EXCEPTION 'Legacy/private scope migration required in % (% suspicious root rows); do not enable deletion',
     r.tab,n USING ERRCODE='23514';
  END IF;
 END LOOP;
 IF total_tables<>24 THEN
  RAISE EXCEPTION 'Private namespace root inventory drift: expected 24 found %',
   total_tables;
 END IF;
END $scan$;
ROLLBACK;
SELECT 'PASS all 24 account-private root tables inspected; no legacy/mixed/owner-mismatched scope data detected; read-only rollback' result;
