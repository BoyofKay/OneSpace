-- Compares every database function after the upgrade with QA's version
-- (supabase/production/qa_function_digests.txt, taken from QA on 21 Nov 2026).
-- Prints differences; it never changes anything.
create temp table qa_digest(line text);
\copy qa_digest from 'supabase/production/qa_function_digests.txt'
create temp view qa_d as
  select left(line, length(line)-11) as fn,
         right(line,10) as digest
    from qa_digest;
create temp view prod_d as
  select p.oid::regprocedure::text as fn,
         left(md5(pg_get_functiondef(p.oid)),10) as digest
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname in ('public','private') and p.prokind='f';
\echo '== Functions in QA but missing in Production after upgrade (must be empty):'
select q.fn from qa_d q left join prod_d p using(fn) where p.fn is null order by 1;
\echo '== Functions whose text differs from QA (review):'
select q.fn from qa_d q join prod_d p using(fn) where p.digest<>q.digest order by 1;
\echo '== Functions only in Production (review):'
select p.fn from prod_d p left join qa_d q using(fn) where q.fn is null order by 1;
\echo '== Scheduled jobs after upgrade:'
select jobname, schedule from cron.job order by 1;
\echo '== Private items per personal space after the data move:'
select 'activities' t, count(*) from public.activities where private_space_id is not null
union all select 'notes', count(*) from public.notes where private_space_id is not null
union all select 'tasks', count(*) from public.tasks where private_space_id is not null
union all select 'space_events', count(*) from public.space_events where private_space_id is not null
union all select 'occasion_plans', count(*) from public.occasion_plans where private_space_id is not null;
