-- QA only: durable space lifecycle orchestration ledger.
-- No jobs are automatically created or executed by this migration.
-- The destructive transition worker will be added ONLY after encrypted
-- archive generation and restore validation pass end-to-end QA.
create table if not exists public.space_lifecycle_jobs(
 id uuid primary key default gen_random_uuid(),
 original_space_id uuid not null, -- no FK: survives retired-space purge
 requested_by uuid not null, -- audit identity preserved after account deletion
 owner_at_request uuid not null,
 invited_partner_at_request uuid,
 action text not null check(action in
   ('partner_leaves','owner_removes_partner','owner_deletes_space',
    'owner_deletes_account','partner_deletes_account')),
 status text not null default 'awaiting_verified_export' check(status in
   ('awaiting_verified_export','exporting','exports_verified',
    'transitioning','retired','cleanup_queued','completed',
    'failed','cancelled')),
 owner_continuous_space boolean not null,
 new_owner_space_id uuid,
 requested_at timestamptz not null default now(),
 last_transition_at timestamptz not null default now(),
 completed_at timestamptz,
 failure_reason text,
 constraint lifecycle_done_timestamp check (
   status<>'completed' or completed_at is not null),
 constraint lifecycle_done_timestamp check (
   status<>'completed' or completed_at is not null)
);
create unique index if not exists one_active_lifecycle_per_space
 on public.space_lifecycle_jobs(original_space_id)
 where status not in ('completed','failed','cancelled');
create index if not exists lifecycle_jobs_status_idx
 on public.space_lifecycle_jobs(status,requested_at);
alter table public.space_lifecycle_jobs enable row level security;
revoke all on public.space_lifecycle_jobs from public,anon,authenticated;
grant select,insert,update on public.space_lifecycle_jobs to service_role;

create table if not exists public.space_lifecycle_job_participants(
 job_id uuid not null references public.space_lifecycle_jobs(id) on delete cascade,
 user_id uuid not null,
 member_role text not null check(member_role in ('owner','partner')),
 primary key(job_id,user_id)
);
create index if not exists lifecycle_participants_user_idx
 on public.space_lifecycle_job_participants(user_id,job_id);
alter table public.space_lifecycle_job_participants enable row level security;
revoke all on public.space_lifecycle_job_participants from public,anon,authenticated;
grant select,insert,update on public.space_lifecycle_job_participants to service_role;

-- Only privileged workers may create/update lifecycle state.
-- The client will later read an authenticated, minimal status RPC.
-- The guard guarantees this schema alone cannot remove a relationship.
