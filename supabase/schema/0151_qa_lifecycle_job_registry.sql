-- QA lifecycle registry. Reconciles the already-deployed staging ledger into
-- the feature-complete R461 migration sequence; never modifies live memberships.
create table if not exists public.space_lifecycle_jobs (
  id uuid primary key default gen_random_uuid(),
  original_space_id uuid not null,
  requested_by uuid not null,
  owner_at_request uuid not null,
  invited_partner_at_request uuid,
  action text not null check (action in (
    'partner_leaves','owner_removes_partner','owner_deletes_space',
    'owner_deletes_account','partner_deletes_account')),
  status text not null default 'awaiting_verified_export' check (status in (
    'awaiting_verified_export','exporting','exports_verified','transitioning',
    'retired','cleanup_queued','completed','failed','cancelled')),
  owner_continuous_space boolean not null,
  new_owner_space_id uuid,
  requested_at timestamptz not null default now(),
  last_transition_at timestamptz not null default now(),
  completed_at timestamptz,
  failure_reason text,
  constraint lifecycle_done_timestamp check (
    status <> 'completed' or completed_at is not null)
);
create table if not exists public.space_lifecycle_job_participants (
  job_id uuid not null references public.space_lifecycle_jobs(id) on delete cascade,
  user_id uuid not null,
  member_role text not null check (member_role in ('owner','partner')),
  primary key (job_id,user_id)
);
create unique index if not exists one_active_lifecycle_per_space
  on public.space_lifecycle_jobs(original_space_id)
  where status not in ('completed','failed','cancelled');
create index if not exists lifecycle_jobs_status_idx
  on public.space_lifecycle_jobs(status,requested_at);
create index if not exists lifecycle_participants_user_idx
  on public.space_lifecycle_job_participants(user_id,job_id);
alter table public.space_lifecycle_jobs enable row level security;
alter table public.space_lifecycle_job_participants enable row level security;
revoke all on table public.space_lifecycle_jobs, public.space_lifecycle_job_participants
  from public,anon,authenticated;
grant select,insert,update,delete on public.space_lifecycle_jobs,
  public.space_lifecycle_job_participants to service_role;
-- No direct user policies: only scoped signed-in RPC functions stage/cancel jobs.
