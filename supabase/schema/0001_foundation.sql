-- OneSpace foundation: accounts (Supabase Auth), profiles, spaces, and secure pairing.
create schema if not exists private;

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default 'Someone' check (char_length(display_name) between 1 and 80),
  locale text not null default 'en' check (locale in ('en','ar')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.spaces (
  id uuid primary key default gen_random_uuid(),
  name text not null default 'Our Space' check (char_length(name) between 1 and 100),
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now()
);

create table public.space_members (
  space_id uuid not null references public.spaces(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  joined_at timestamptz not null default now(),
  primary key (space_id, user_id),
  unique(user_id)
);

create index space_members_by_space on public.space_members(space_id);

create table public.space_invitations (
  id uuid primary key default gen_random_uuid(),
  space_id uuid not null references public.spaces(id) on delete cascade,
  invited_by uuid not null references auth.users(id),
  token text not null unique,
  expires_at timestamptz not null,
  accepted_by uuid references auth.users(id),
  accepted_at timestamptz,
  revoked_at timestamptz,
  created_at timestamptz not null default now()
);

create index space_invitations_by_space on public.space_invitations(space_id);

-- Internal RLS helper; never expose the private schema through the Data API.
create or replace function private.is_space_member(p_space_id uuid)
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.space_members
    where space_id = p_space_id and user_id = (select auth.uid())
  );
$$;

-- Auth signup trigger to create a profile for each new user.
create or replace function private.handle_new_user()
returns trigger
language plpgsql security definer
set search_path = ''
as $$
begin
  insert into public.profiles(id, display_name)
  values (
    new.id,
    coalesce(nullif(left(btrim(new.raw_user_meta_data ->> 'display_name'), 80), ''), 'Someone')
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

create trigger onespace_auth_user_created
after insert on auth.users
for each row execute function private.handle_new_user();

-- Foundation for any existing users (if present).
insert into public.profiles(id, display_name)
select id, coalesce(nullif(left(btrim(raw_user_meta_data ->> 'display_name'),80),''), 'Someone')
from auth.users on conflict(id) do nothing;

alter table public.profiles enable row level security;
alter table public.spaces enable row level security;
alter table public.space_members enable row level security;
alter table public.space_invitations enable row level security;

create policy "Read my profile and my partner profile" on public.profiles
for select to authenticated
using (
  id = (select auth.uid())
  or exists (
    select 1 from public.space_members theirs
    where theirs.user_id = profiles.id
      and private.is_space_member(theirs.space_id)
  )
);

create policy "Create my own profile" on public.profiles
for insert to authenticated
with check (id = (select auth.uid()));

create policy "Update my own profile" on public.profiles
for update to authenticated
using (id = (select auth.uid()))
with check (id = (select auth.uid()));

create policy "Read only my shared space" on public.spaces
for select to authenticated
using (private.is_space_member(id));

create policy "Read memberships only in my space" on public.space_members
for select to authenticated
using (private.is_space_member(space_id));

create policy "Read invitations I issued" on public.space_invitations
for select to authenticated
using (
  invited_by = (select auth.uid())
  and private.is_space_member(space_id)
);

-- Only narrowly scoped server-side functions may alter spaces and membership.
create or replace function public.create_space()
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

create or replace function public.create_invitation(p_space_id uuid)
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

create or replace function public.accept_invitation(p_token text)
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
  select * into v_inv from public.space_invitations
  where token = lower(btrim(p_token)) for update;
  if not found or v_inv.accepted_at is not null or v_inv.revoked_at is not null
     or v_inv.expires_at <= now() then
    raise exception 'Invitation is invalid or expired';
  end if;
  if v_inv.invited_by = v_user then
    raise exception 'You cannot accept your own invitation';
  end if;
  perform 1 from public.spaces where id=v_inv.space_id for update;
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

-- Least privilege API grants; no client can directly add itself as a partner.
revoke all on public.profiles, public.spaces, public.space_members, public.space_invitations from anon, authenticated;
grant select, insert, update on public.profiles to authenticated;
grant select on public.spaces, public.space_members, public.space_invitations to authenticated;
grant usage on schema private to authenticated;
revoke all on function private.is_space_member(uuid) from public, anon;
grant execute on function private.is_space_member(uuid) to authenticated;
revoke all on function public.create_space(), public.create_invitation(uuid), public.accept_invitation(text) from public, anon;
grant execute on function public.create_space(), public.create_invitation(uuid), public.accept_invitation(text) to authenticated;
