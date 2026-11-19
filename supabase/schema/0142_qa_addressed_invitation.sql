-- QA-first D05/D07: invitation identity is a *verified email address*.
-- No archive purging or destructive space lifecycle operations.
alter table public.space_invitations
  add column if not exists invited_email text,
  add column if not exists delivery_status text not null default 'pending',
  add column if not exists email_sent_at timestamptz;
alter table public.space_invitations drop constraint if exists invited_email_format;
alter table public.space_invitations
  add constraint invited_email_format check (
    invited_email is null or
    (length(invited_email) between 3 and 254
     and invited_email = lower(btrim(invited_email))
     and invited_email ~ '^[^[:space:]@<>]+@[^[:space:]@<>]+[.][^[:space:]@<>]+$'));
alter table public.space_invitations drop constraint if exists delivery_status_values;
alter table public.space_invitations add constraint delivery_status_values check
  (delivery_status in ('pending','sent','send_failed','accepted','revoked'));
create index if not exists space_invitation_recipient_idx
 on public.space_invitations(space_id,invited_email)
 where accepted_at is null and revoked_at is null;

-- The existing unaddressed create_invitation RPC is superseded in QA.
-- It must not mint a recipient-free code for older clients.
create or replace function private.create_invitation(p_space_id uuid)
returns text language plpgsql security definer set search_path = ''
as $$
begin
  raise exception 'Update OneSpace QA to invite a specific email address';
end $$;

create or replace function private.create_addressed_invitation(
  p_space_id uuid, p_email text, p_replace boolean default false
) returns text language plpgsql security definer set search_path = ''
as $$
declare
  me uuid := auth.uid();
  address text := lower(btrim(coalesce(p_email,'')));
  active_inv public.space_invitations%rowtype;
  minted text;
begin
  if me is null then raise exception 'Sign in required'; end if;
  if length(address) not between 3 and 254 or
     address !~ '^[^[:space:]@<>]+@[^[:space:]@<>]+[.][^[:space:]@<>]+$' then
    raise exception 'Enter a valid partner email';
  end if;
  if exists(select 1 from auth.users where id=me and lower(email)=address) then
    raise exception 'You cannot invite yourself';
  end if;
  -- The original creator is the only one allowed to manage invitations.
  perform 1 from public.spaces s where s.id=p_space_id and s.created_by=me for update;
  if not found or not exists(
     select 1 from public.space_members where space_id=p_space_id and user_id=me)
  then raise exception 'Only the space owner can invite a partner'; end if;
  if (select count(*) from public.space_members where space_id=p_space_id)>=2 then
    raise exception 'This space already has two partners'; end if;
  select * into active_inv from public.space_invitations
    where space_id=p_space_id and accepted_at is null and revoked_at is null
      and expires_at > now()
    order by created_at desc limit 1 for update;
  if found then
    if not p_replace and active_inv.invited_email=address then
      return active_inv.token; -- Idempotent resend, original expiry.
    end if;
    if not p_replace then
      raise exception 'An invitation is already active. Confirm replacement first';
    end if;
  end if;
  update public.space_invitations
  set revoked_at=now(),delivery_status='revoked'
  where space_id=p_space_id and accepted_at is null and revoked_at is null;
  minted := replace(gen_random_uuid()::text,'-','')||
            replace(gen_random_uuid()::text,'-','');
  insert into public.space_invitations
    (space_id,invited_by,invited_email,token,expires_at,delivery_status)
  values(p_space_id,me,address,minted,now()+interval '48 hours','pending');
  return minted;
end $$;

create or replace function public.create_addressed_invitation(
  p_space_id uuid,p_email text,p_replace boolean default false
) returns text language sql security invoker set search_path = ''
as $$select private.create_addressed_invitation(p_space_id,p_email,p_replace)$$;
revoke all on function private.create_addressed_invitation(uuid,text,boolean)
 from public,anon;
revoke all on function public.create_addressed_invitation(uuid,text,boolean)
 from public,anon;
grant execute on function private.create_addressed_invitation(uuid,text,boolean)
 to authenticated;
grant execute on function public.create_addressed_invitation(uuid,text,boolean)
 to authenticated;

-- Enforce recipient email on *every* joining path: link, QR, manual code.
create or replace function private.accept_invitation(p_token text)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare
 me uuid := auth.uid();
 inv public.space_invitations%rowtype;
 verified_email text;
begin
 if me is null then raise exception 'Sign in required'; end if;
 select lower(email) into verified_email from auth.users
 where id=me and email_confirmed_at is not null;
 if verified_email is null then
   raise exception 'Verify your account email before joining'; end if;
 if exists(select 1 from public.space_members where user_id=me) then
   raise exception 'You already belong to a space'; end if;
 select * into inv from public.space_invitations
 where token=lower(btrim(p_token));
 if not found then raise exception 'Invitation is invalid or expired'; end if;
 -- Parent then child locks are consistent with issuing/replacing.
 perform 1 from public.spaces where id=inv.space_id for update;
 select * into inv from public.space_invitations where id=inv.id for update;
 if not found or inv.accepted_at is not null or inv.revoked_at is not null
     or inv.expires_at<=now() then
   raise exception 'Invitation is invalid or expired'; end if;
 if inv.invited_by=me then raise exception 'You cannot join your own invitation'; end if;
 if inv.invited_email is null or inv.invited_email<>verified_email then
   raise exception 'This invitation is for a different verified email'; end if;
 if (select count(*) from public.space_members where space_id=inv.space_id)>=2 then
   raise exception 'This space is already full'; end if;
 insert into public.space_members(space_id,user_id) values(inv.space_id,me);
 update public.space_invitations set accepted_by=me,
   accepted_at=now(),delivery_status='accepted' where id=inv.id;
 update public.space_invitations set revoked_at=now(),delivery_status='revoked'
 where space_id=inv.space_id and id<>inv.id
   and accepted_at is null and revoked_at is null;
 return inv.space_id;
end $$;

-- For consistency, manual revoke must also update status.
create or replace function private.revoke_pending_invitation(p_space_id uuid)
returns integer language plpgsql security definer set search_path = ''
as $
declare me uuid := auth.uid();
        changed integer := 0;
begin
 perform 1 from public.spaces where id=p_space_id and created_by=me for update;
 if not found then raise exception 'Only the owner can revoke an invitation'; end if;
 update public.space_invitations
   set revoked_at=now(), delivery_status='revoked'
 where space_id=p_space_id and accepted_at is null and revoked_at is null;
 get diagnostics changed = row_count;
 return changed;
end $;
