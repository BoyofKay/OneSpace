-- 0325 (QA only, owner decision 27 Nov 2026): the fictional demo partner is Adam, not Omar.
-- Renames the visible name in the demo seed functions (EN 'Omar' -> 'Adam', AR 'عمر' -> 'آدم').
-- The internal role key 'omar' and the demo login are unchanged. Applied to QA on 27 Nov 2026.
do $$
declare def text;
begin
  def := replace(pg_get_functiondef('private.demo_reset(text)'::regprocedure), 'Omar', 'Adam');
  execute def;
  def := replace(replace(pg_get_functiondef('private.demo_arabic(uuid)'::regprocedure), 'Omar', 'Adam'), 'عمر', 'آدم');
  execute def;
end $$;
