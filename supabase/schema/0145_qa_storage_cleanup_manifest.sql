-- QA-only temporary maintenance listing. It never deletes Storage metadata.
-- Callable solely by service_role; refuses if any application records exist.
create or replace function public.qa_storage_cleanup_manifest_service()
returns table(bucket_id text,object_path text)
language plpgsql security invoker set search_path to '' as $$
declare
  t record;
  live_rows boolean;
begin
  if current_user <> 'service_role' then
    raise exception 'Service role only';
  end if;
  for t in
    select tablename from pg_catalog.pg_tables
    where schemaname='public' and tablename not in
       ('profiles','spaces','space_members')
  loop
    execute format('select exists(select 1 from public.%I)',t.tablename)
      into live_rows;
    if live_rows then
      raise exception 'QA media cleanup refused: new application records found';
    end if;
  end loop;
  return query
    select o.bucket_id, o.name from storage.objects o
    where o.bucket_id in (
     'onespace-activity-media','onespace-activity-voice',
     'onespace-memory-photos','onespace-note-images',
     'onespace-trip-documents','onespace-share-in')
      and o.created_at<now()-interval '24 hours'
    order by o.bucket_id,o.name limit 100;
end $$;
revoke all on function public.qa_storage_cleanup_manifest_service() from public,anon,authenticated;
grant execute on function public.qa_storage_cleanup_manifest_service() to service_role;