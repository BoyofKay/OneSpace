-- QA 0224: the first durable and honest stage of backend archival.
-- Creates a recipient-specific 69-family source inventory; never reports an
-- archive as exported, encrypted, restorable, downloadable or ready.
-- No lifecycle action / membership / account deletion is executed here.
create table if not exists public.qa_archive_job_progress (
  id uuid primary key default gen_random_uuid(),
  lifecycle_job_id uuid not null references public.space_lifecycle_jobs(id),
  original_space_id uuid not null references public.spaces(id),
  recipient_id uuid not null references auth.users(id),
  archive_kind text not null check (archive_kind in ('private','shared')),
  status text not null default 'queued' check(status in
    ('queued','inventory_complete','inventory_blocked','cancelled')),
  records_identified bigint check(records_identified is null or records_identified >= 0),
  records_archived bigint not null default 0 check(records_archived >= 0),
  bytes_encrypted bigint not null default 0 check(bytes_encrypted >= 0),
  inventory_sha256 text check(inventory_sha256 is null or inventory_sha256 ~ '^[0-9a-f]{64}$'),
  inventoried_at timestamptz,
  last_transition_at timestamptz not null default now(),
  error_code text,
  unique(lifecycle_job_id,recipient_id,archive_kind),
  constraint archive_progress_counts_not_exaggerated check
    (records_identified is null or records_archived <= records_identified),
  constraint archive_progress_no_fake_issued_archive check
    (records_archived=0 and bytes_encrypted=0)
);
alter table public.qa_archive_job_progress enable row level security;
revoke all on public.qa_archive_job_progress from public,anon,authenticated;
grant select on public.qa_archive_job_progress to authenticated;
create policy "Each original user sees only their own inventory progress"
  on public.qa_archive_job_progress for select to authenticated
  using (recipient_id=(select auth.uid()));

-- Callable only with service_role, never with the client publishable key.
-- A complete, validated per-recipient census is based on the signed member
-- snapshot in space_lifecycle_job_participants and the immutable original
-- space ID. No private record content or other-user counts are exposed.
create or replace function public.qa_archive_inventory_service(p_limit int default 4)
 returns jsonb language plpgsql security definer set search_path = ''
as $fn$
declare
 j record; member record; r jsonb; total_private bigint; total_shared bigint;
 processed int:=0; inventoried int:=0; blocked int:=0; original_sub text;
begin
 if p_limit<1 or p_limit>10 then raise exception 'Invalid inventory batch size';end if;
 original_sub := current_setting('request.jwt.claim.sub',true);
 for j in
  select x.id,x.original_space_id from public.space_lifecycle_jobs x
  where x.status='awaiting_verified_export'
    and not exists (
     select 1 from public.qa_archive_job_progress pr
     where pr.lifecycle_job_id=x.id)
  order by x.requested_at limit p_limit for update skip locked
 loop
  processed:=processed+1;
  for member in
   select p.user_id from public.space_lifecycle_job_participants p
   where p.job_id=j.id order by p.user_id
  loop
   begin
    if not exists(select 1 from public.space_members sm
      where sm.user_id=member.user_id and sm.space_id=j.original_space_id) then
      raise exception 'Original membership boundary has changed';
    end if;
    perform set_config('request.jwt.claim.sub',member.user_id::text,true);
    r:=private.qa_archive_source_coverage_report();
    if r->>'source_space_id'<>j.original_space_id::text
       or r->>'recipient_id'<>member.user_id::text
       or (r->>'table_types_accounted_for')::int<>69
       or r->>'source_coverage_sha256' !~ '^[0-9a-f]{64}$' then
      raise exception 'Archive source census failed provenance check';
    end if;
    total_private:=(r->>'private_source_rows_counted')::bigint;
    total_shared:=(r->>'recipient_visible_shared_only_rows_counted')::bigint
      +(r->>'recipient_visible_mixed_shared_rows_counted')::bigint;
    if total_private<0 or total_shared<0 then
      raise exception 'Negative source inventory';
    end if;
    insert into public.qa_archive_job_progress
      (lifecycle_job_id,original_space_id,recipient_id,archive_kind,status,
       records_identified,inventory_sha256,inventoried_at)
    values
      (j.id,j.original_space_id,member.user_id,'private',
       'inventory_complete',total_private,r->>'source_coverage_sha256',now()),
      (j.id,j.original_space_id,member.user_id,'shared',
       'inventory_complete',total_shared,r->>'source_coverage_sha256',now())
    on conflict (lifecycle_job_id,recipient_id,archive_kind) do nothing;
    inventoried:=inventoried+1;
   exception when others then
    -- Do not export or pretend success if any 69-family check fails. Avoid
    -- storing raw SQL errors or record details in a user-visible table.
    insert into public.qa_archive_job_progress
      (lifecycle_job_id,original_space_id,recipient_id,archive_kind,status,error_code)
    values
      (j.id,j.original_space_id,member.user_id,'private',
       'inventory_blocked','source_census_incomplete'),
      (j.id,j.original_space_id,member.user_id,'shared',
       'inventory_blocked','source_census_incomplete')
    on conflict (lifecycle_job_id,recipient_id,archive_kind) do nothing;
    blocked:=blocked+1;
   end;
  end loop;
 end loop;
 perform set_config('request.jwt.claim.sub',coalesce(original_sub,''),true);
 return jsonb_build_object('jobs_examined',processed,'recipients_inventoried',
   inventoried,'recipients_blocked',blocked,
   'encrypted_archives_created',0,'lifecycle_changes_executed',0);
end $fn$;
revoke all on function public.qa_archive_inventory_service(int) from public,anon,authenticated;
grant execute on function public.qa_archive_inventory_service(int) to service_role;

create or replace function private.qa_cancel_inventory_with_lifecycle()
returns trigger language plpgsql security definer set search_path=''
as $fn$
begin
 if new.status='cancelled' and old.status is distinct from new.status then
  update public.qa_archive_job_progress p
  set status='cancelled',last_transition_at=now()
  where p.lifecycle_job_id=new.id and p.status in ('queued','inventory_complete','inventory_blocked');
 end if;
 return new;
end $fn$;
drop trigger if exists qa_lifecycle_inventory_cancel on public.space_lifecycle_jobs;
create trigger qa_lifecycle_inventory_cancel after update of status
on public.space_lifecycle_jobs for each row
execute function private.qa_cancel_inventory_with_lifecycle();
