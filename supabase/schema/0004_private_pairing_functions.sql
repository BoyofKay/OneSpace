-- Keep the Data API RPC surface SECURITY INVOKER; authorize privileged work inside a non-exposed private schema.
-- Fix lock ordering for invitation creation and acceptance to avoid space/invitation deadlocks.

create or replace function private.create_space()
returns uuid
language plpgsql security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_space uuid;
begin
  if v_user is null then
    raise exception 'Sign in required';
  end if;
  if exists (select 1 from public.space_members where user_id = v_user) then
    raise exception 'You already have a shared space';
  end if;
  insert into public.spaces (created_by) values(v_user) returning id into v_space;
  insert into public.space_members (space_id, user_id) values(v_space,v_user);
  return v_space;
end;
$$;

create or replace function private.create_invitation(p_space_id uuid)
returns text
language plpgsql security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_token text;
begin
  if v_user is null or not private.is_space_member(p_space_id) then
    raise exception 'Shared space not found';
  end if;
  perform 1 from public.spaces where id=p_space_id for update;
  if (select count(*) from public.space_members where space_id=p_space_id) >= 2 then
    raise exception 'This shared space already has two partners';
  end if;
  update public.space_invitations
    set revoked_at=now()
    where space_id=p_space_id and accepted_at is null and revoked_at is null;
  v_token := replace(gen_random_uuid()::text,'-','') || replace(gen_random_uuid()::text,'-','');
  insert into public.space_invitations (space_id, invited_by, token, expires_at)
  values (p_space_id,v_user,v_token,now()+interval '48 hours');
  return v_token;
end;
$$;

create or replace function private.accept_invitation(p_token text)
returns uuid
language plpgsql security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_inv public.space_invitations%rowtype;
begin
  if v_user is null then
    raise exception 'Sign in required';
  end if;
  if exists (select 1 from public.space_members where user_id = v_user) then
    raise exception 'You already have a shared space';
  end if;
  -- Find the parent without locking the child first.
  select * into v_inv from public.space_invitations
  where token = lower(btrim(p_token));
  if not found then
    raise exception 'Invitation is invalid or expired';
  end if;
  -- Same lock order as create_invitation: parent space, then invitation.
  perform 1 from public.spaces where id=v_inv.space_id for update;
  select * into v_inv from public.space_invitations
  where id=v_inv.id for update;
  if not found or v_inv.accepted_at is not null or v_inv.revoked_at is not null
     or v_inv.expires_at <= now() then
    raise exception 'Invitation is invalid or expired';
  end if;
  if v_inv.invited_by = v_user then
    raise exception 'You cannot accept your own invitation';
  end if;
  if (select count(*) from public.space_members where space_id=v_inv.space_id) >= 2 then
    raise exception 'This shared space is full';
  end if;
  insert into public.space_members (space_id,user_id) values(v_inv.space_id,v_user);
  update public.space_invitations set accepted_by=v_user,accepted_at=now()
  where id=v_inv.id;
  update public.space_invitations set revoked_at=now()
  where space_id=v_inv.space_id and id<>v_inv.id and accepted_at is null and revoked_at is null;
  return v_inv.space_id;
end;
$$;


-- Public RPCs are minimal, non-privileged wrappers accessible to authenticated callers.
create or replace function public.create_space()
returns uuid language sql security invoker set search_path = ''
as $$ select private.create_space(); $$;

create or replace function public.create_invitation(p_space_id uuid)
returns text language sql security invoker set search_path = ''
as $$ select private.create_invitation(p_space_id); $$;

create or replace function public.accept_invitation(p_token text)
returns uuid language sql security invoker set search_path = ''
as $$ select private.accept_invitation(p_token); $$;

revoke all on function private.create_space(), private.create_invitation(uuid), private.accept_invitation(text)
from public, anon, authenticated;
grant execute on function private.create_space(), private.create_invitation(uuid), private.accept_invitation(text)
to authenticated;
revoke all on function public.create_space(), public.create_invitation(uuid), public.accept_invitation(text)
from public, anon;
grant execute on function public.create_space(), public.create_invitation(uuid), public.accept_invitation(text)
to authenticated;
