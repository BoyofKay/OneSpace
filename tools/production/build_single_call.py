"""Builds one SQL text for a single Supabase SQL call (one transaction).

  python3 tools/production/build_single_call.py dry_run OUT.sql
      upgrade + checks, then raises an error on purpose so everything rolls back.
      The error message carries the check results.

The SQL runs as one implicit transaction: any error, including the final
dry-run error, undoes every statement in it.
"""
import pathlib, sys

root = pathlib.Path(__file__).resolve().parents[2]
mode, out = sys.argv[1], pathlib.Path(sys.argv[2])
assert mode == 'dry_run', 'only dry_run is built here'
up = (root / 'supabase/production/upgrade.sql').read_text()
up = '\n'.join(l for l in up.split('\n') if not l.startswith('\\'))
dig = []
for line in (root / 'supabase/production/qa_function_digests.txt').read_text().splitlines():
    if line.strip():
        fn, d = line[:-11], line[-10:]
        dig.append("(%s,%s)" % ("'" + fn.replace("'", "''") + "'", "'" + d + "'"))
summary = """
create temp table qa_d(fn text, digest text) on commit drop;
insert into qa_d values %s;
do $sum$
declare missing text; diff text; ndiff int; extra text; jobs text; moved text; qa_host int;
begin
  select string_agg(q.fn, ', ' order by q.fn) into missing from qa_d q
   where not exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
                     where n.nspname in ('public','private') and p.oid::regprocedure::text=q.fn);
  select count(*), string_agg(q.fn, ', ' order by q.fn) into ndiff, diff from qa_d q
    join pg_proc p on p.oid::regprocedure::text=q.fn
    join pg_namespace n on n.oid=p.pronamespace and n.nspname in ('public','private')
   where p.prokind='f' and left(md5(pg_get_functiondef(p.oid)),10)<>q.digest;
  select string_agg(p.oid::regprocedure::text, ', ') into extra from pg_proc p
    join pg_namespace n on n.oid=p.pronamespace
   where n.nspname in ('public','private') and p.prokind='f'
     and not exists(select 1 from qa_d q where q.fn=p.oid::regprocedure::text);
  select string_agg(jobname, ', ' order by jobname) into jobs from cron.job;
  select count(*) into qa_host from cron.job where command like '%%ugwrpeduzyzrujkizqfo%%';
  select format('activities=%%s notes=%%s tasks=%%s space_events=%%s occasion_plans=%%s',
    (select count(*) from public.activities where private_space_id is not null),
    (select count(*) from public.notes where private_space_id is not null),
    (select count(*) from public.tasks where private_space_id is not null),
    (select count(*) from public.space_events where private_space_id is not null),
    (select count(*) from public.occasion_plans where private_space_id is not null)) into moved;
  raise exception E'DRY RUN FINISHED, ROLLED BACK\\nmissing: %%\\ndiffer (%%): %%\\nprod-only: %%\\ncron: %%\\ncron at QA: %%\\nprivate: %%',
    coalesce(missing,'none'), ndiff, left(coalesce(diff,'none'),3000), coalesce(extra,'none'),
    coalesce(jobs,'none'), qa_host, moved;
end
$sum$;
""" % ',\n'.join(dig)
out.write_text(up + '\n' + summary)
print(out, out.stat().st_size)
