-- QA R-lifecycle stage 1: non-destructive, role-authorized requests.
-- These functions DO NOT remove partners, accounts, spaces, or content.
-- Finalization remains prohibited until encrypted archives/media are verified.
create or replace function public.my_space_lifecycle_status()
returns jsonb language plpgsql security definer set search_path to '' as $$
declare
  me uuid := auth.uid();
  sid uuid;
  owner_id uuid;
  member_count integer;
  archive_count integer := 0;
  expected_count integer := 0;
  pending jsonb;
begin
  if me is null then raise exception 'Sign in required'; end if;
  if (select count(*) from public.space_members where user_id=me) > 1 then
    raise exception 'Multiple active memberships require support';
  end if;
  select sm.space_id, s.created_by into sid,owner_id
  from public.space_members sm join public.spaces s on s.id=sm.space_id
  where sm.user_id=me limit 1;
  if sid is null then return jsonb_build_object('has_space',false,
    'role','unpaired','member_count',0,'can_leave',false,
    'can_remove_partner',false,'can_delete_space',false,
    'active_job',null,'archives_expected',0,'archives_verified',0,
    'safe_to_finalize',false); end if;
  select count(*) into member_count from public.space_members where space_id=sid;
  expected_count := member_count*2;
  select count(distinct (a.recipient_id,a.archive_kind)) into archive_count
  from public.space_archives a
  where a.old_space_id=sid
    and a.recipient_id in (select user_id from public.space_members where space_id=sid)
    and a.archive_kind in ('private','shared')
    and a.encrypted_bytes_verified
    and a.ciphertext_sha256 ~ '^[0-9a-f]{64}$'
    and a.byte_length>0
    and a.ready_at is not null
    and a.status in ('ready','purge_due')
    and (a.status<>'ready' or a.expires_at>now())
    and exists (select 1 from storage.objects o
      where o.bucket_id='onespace-archives' and o.name=a.encrypted_object_path);
  select jsonb_build_object('id',j.id,'action',j.action,'status',j.status,
    'requested_by_me',j.requested_by=me,'requested_at',j.requested_at)
    into pending
  from public.space_lifecycle_jobs j
  where j.original_space_id=sid and j.status not in ('completed','failed','cancelled')
  order by j.requested_at desc limit 1;
  return jsonb_build_object('has_space',true,'role',case when owner_id=me then 'owner' else 'partner' end,
    'member_count',member_count,'can_leave',owner_id<>me,
    'can_remove_partner',owner_id=me and member_count=2,
    'can_delete_space',owner_id=me,'active_job',pending,
    'archives_expected',expected_count,'archives_verified',archive_count,
    'safe_to_finalize',false,
    'reason','Actual separation requires verified encrypted private/shared exports, media integrity and an authorized transition worker');
end $$;
revoke all on function public.my_space_lifecycle_status() from public,anon;
grant execute on function public.my_space_lifecycle_status() to authenticated;

create or replace function public.request_space_lifecycle_action(p_action text)
returns jsonb language plpgsql security definer set search_path to '' as $$
declare
  me uuid := auth.uid();
  sid uuid;
  owner_id uuid;
  partner_id uuid;
  member_count integer;
  pending_id uuid;
  job_id uuid;
begin
  if me is null then raise exception 'Sign in required'; end if;
  if p_action not in ('partner_leaves','owner_removes_partner','owner_deletes_space') then
    raise exception 'Unsupported space action';
  end if;
  if (select count(*) from public.space_members where user_id=me)<>1 then
    raise exception 'A single active space is required';
  end if;
  select s.id,s.created_by into sid,owner_id
  from public.spaces s join public.space_members sm on sm.space_id=s.id
  where sm.user_id=me for update of s;
  if sid is null then raise exception 'Not a member of a space'; end if;
  select count(*) into member_count from public.space_members where space_id=sid;
  select user_id into partner_id from public.space_members
  where space_id=sid and user_id<>owner_id limit 1;
  if member_count<1 or member_count>2 then raise exception 'Invalid membership state'; end if;
  if p_action='partner_leaves' and (me=owner_id or member_count<>2) then
    raise exception 'Only the invited partner can leave';
  end if;
  if p_action='owner_removes_partner' and (me<>owner_id or member_count<>2) then
    raise exception 'Only the owner of a paired space can remove the partner';
  end if;
  if p_action='owner_deletes_space' and me<>owner_id then
    raise exception 'Only the original owner can delete the space';
  end if;
  select j.id into pending_id from public.space_lifecycle_jobs j
   where j.original_space_id=sid
   and j.status not in ('completed','failed','cancelled') limit 1;
  if pending_id is not null then raise exception 'A lifecycle request is already in progress'; end if;
  insert into public.space_lifecycle_jobs
    (original_space_id,requested_by,owner_at_request,invited_partner_at_request,
     action,status,owner_continuous_space)
   values (sid,me,owner_id,partner_id,p_action,'awaiting_verified_export',
     p_action<>'owner_deletes_space') returning id into job_id;
  insert into public.space_lifecycle_job_participants(job_id,user_id,member_role)
  select job_id,user_id,case when user_id=owner_id then 'owner' else 'partner' end
  from public.space_members where space_id=sid;
  return jsonb_build_object('id',job_id,'status','awaiting_verified_export',
    'action',p_action,'separation_completed',false,
    'message','Request recorded. Members and data remain unchanged until secure archive verification and transition.');
end $$;
revoke all on function public.request_space_lifecycle_action(text) from public,anon;
grant execute on function public.request_space_lifecycle_action(text) to authenticated;

create or replace function public.cancel_space_lifecycle_action(p_job_id uuid)
returns boolean language plpgsql security definer set search_path to '' as $$
declare me uuid := auth.uid(); updated_rows integer;
begin
  if me is null then raise exception 'Sign in required'; end if;
  update public.space_lifecycle_jobs j
  set status='cancelled',last_transition_at=now()
  where j.id=p_job_id and j.requested_by=me
    and j.status='awaiting_verified_export'
    and not exists(select 1 from public.space_archives a where a.old_space_id=j.original_space_id
      and a.status in ('ready','purge_due','purged'));
  get diagnostics updated_rows = row_count;
  return updated_rows=1;
end $$;
revoke all on function public.cancel_space_lifecycle_action(uuid) from public,anon;
grant execute on function public.cancel_space_lifecycle_action(uuid) to authenticated;