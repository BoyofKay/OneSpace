-- 0319: keep the fictional demo couple's reset (private.demo_reset) working under
-- the private/shared ownership rules (ADR 2026-11-20).
-- * "Lina's birthday" is Omar's private surprise, so it now lives in Omar's own
--   private space (private_space_id = Omar, no shared space). The occasion budget
--   check rejected the old private-occasion-inside-the-shared-space row, which
--   made every reset fail.
-- * The demo accounts accept the current Terms version (2026-11-22).
-- Rewrites the function in place, like 0133. QA only; demo accounts only.
do $do$
declare def text; before text;
begin
  select pg_get_functiondef(p.oid) into def from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'private' and p.proname = 'demo_reset';
  before := def;
  def := replace(def,
    'insert into public.occasion_plans (space_id, created_by, title, occasion_on, annual, kind, visibility, status, prep_lead_days, budget, currency, honoree_name, notes)
    values (sp, o, ''Lina''''s birthday''',
    'insert into public.occasion_plans (space_id, private_space_id, created_by, title, occasion_on, annual, kind, visibility, status, prep_lead_days, budget, currency, honoree_name, notes)
    values (null, o, o, ''Lina''''s birthday''');
  if def = before then raise exception 'demo_reset occasion insert not found'; end if;
  def := replace(def, 'terms_version = ''2026-11-16''', 'terms_version = ''2026-11-22''');
  execute def;
end $do$;
