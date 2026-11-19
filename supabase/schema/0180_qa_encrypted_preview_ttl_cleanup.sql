-- QA 0180: expiry cleanup for 24h encrypted *preview* Storage files.
-- The existing archive janitor hourly schedule will call these service RPCs.
-- No live private/shared rows or real lifecycle archives may be touched.
create or replace function public.qa_previews_due_for_purge_service()
returns table(preview_id uuid,object_path text)
language plpgsql security invoker set search_path='' as $fn$
begin
 if current_user<>'service_role' then raise exception 'Service role only';end if;
 return query
 select p.id,p.object_path
 from public.qa_structured_preview_staging p
 where p.status in ('pending','available','failed')
   and p.expires_at<=now()
 order by p.expires_at,p.id limit 100;
end $fn$;
revoke all on function public.qa_previews_due_for_purge_service()
 from public,anon,authenticated;
grant execute on function public.qa_previews_due_for_purge_service()
 to service_role;

create or replace function public.qa_preview_finish_purge_service(p_id uuid)
returns boolean language plpgsql security invoker set search_path='' as $fn$
begin
 if current_user<>'service_role' then raise exception 'Service role only';end if;
 update public.qa_structured_preview_staging
  set status='purged',verified_storage_bytes=false
 where id=p_id and expires_at<=now()
   and status in ('pending','available','failed');
 return found;
end $fn$;
revoke all on function public.qa_preview_finish_purge_service(uuid)
 from public,anon,authenticated;
grant execute on function public.qa_preview_finish_purge_service(uuid)
 to service_role;

-- The preview is never a space_archives row and this does not enable lifecycle.
