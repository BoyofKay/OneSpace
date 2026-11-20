-- QA regression: run in an explicit transaction and roll back every change.
begin;
do $check$
declare jobs integer; n integer; failed integer; owner uuid; job uuid;
begin
 if has_function_privilege('authenticated',
    'public.qa_archive_inventory_service(integer)','EXECUTE')
 or has_function_privilege('anon',
    'public.qa_archive_inventory_service(integer)','EXECUTE') then
  raise exception 'Client can execute privileged inventory worker';
 end if;
 select count(*) into jobs from public.space_lifecycle_jobs
  where status='awaiting_verified_export';
 select count(*) into n from public.qa_archive_job_progress;
 if exists(select 1 from public.qa_archive_job_progress
   where records_archived<>0 or bytes_encrypted<>0
     or (status='inventory_complete' and
       (records_identified is null or inventory_sha256 is null
         or inventoried_at is null))) then
   raise exception 'Source inventory falsely claims archived bytes';
 end if;
 if exists(select 1 from public.qa_archive_job_progress pr
   where not exists(select 1 from public.space_lifecycle_job_participants mem
    where mem.job_id=pr.lifecycle_job_id and mem.user_id=pr.recipient_id))
 then raise exception 'Archive progress leaks to nonparticipant';end if;
 select j.id into job from public.space_lifecycle_jobs j
 where j.status='awaiting_verified_export' order by j.requested_at limit 1;
 if job is not null then
  update public.space_lifecycle_jobs set status='cancelled' where id=job;
  if exists(select 1 from public.qa_archive_job_progress
     where lifecycle_job_id=job and status<>'cancelled') then
    raise exception 'Cancelled action left inventory rows active';
  end if;
 end if;
end $check$;
rollback;
