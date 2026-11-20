-- QA 0227: account-owned private namespace, separate from couple-owned spaces.
-- Safe additive foundation: existing object tables and original membership
-- flows remain unchanged until each content module adopts explicit scope FKs.
create table if not exists public.user_private_spaces (
  owner_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);
comment on table public.user_private_spaces is
  'Exactly one account-owned private namespace per user, independent of pairing';
alter table public.user_private_spaces enable row level security;
revoke all on public.user_private_spaces from public,anon,authenticated;
grant select on public.user_private_spaces to authenticated;
drop policy if exists "Read own private space only" on public.user_private_spaces;
create policy "Read own private space only"
on public.user_private_spaces for select to authenticated
using(owner_id=(select auth.uid()));

create or replace function private.create_private_space_for_new_user()
returns trigger language plpgsql security definer set search_path=''
as $fn$
begin
  if new.id is null then raise exception 'New user ID required';end if;
  insert into public.user_private_spaces(owner_id) values(new.id)
  on conflict(owner_id) do nothing;
  return new;
end
$fn$;
revoke all on function private.create_private_space_for_new_user()
  from public,anon,authenticated;
drop trigger if exists create_onespace_private_space on auth.users;
create trigger create_onespace_private_space
after insert on auth.users
for each row execute function private.create_private_space_for_new_user();

-- Historical accounts only; no private content is moved in this migration.
insert into public.user_private_spaces(owner_id)
select id from auth.users where deleted_at is null
on conflict(owner_id) do nothing;

-- Read-only resolver for future unified OneSpace screens. Every account has a
-- private scope even when it is unpaired. Existing public.spaces remains the
-- coupled/legacy scope; a singleton legacy space is NOT a new shared couple.
create or replace function public.my_storage_scopes()
returns jsonb language sql stable security invoker set search_path=''
as $fn$
with me as (select auth.uid() id),
membership as (
 select sm.space_id
 from public.space_members sm, me
 where sm.user_id=me.id
 order by sm.joined_at desc
 limit 1
), pair as (
 select m.space_id, count(*) member_count
 from public.space_members m
 join membership own on own.space_id=m.space_id
 group by m.space_id
)
select jsonb_build_object(
 'private_space_id',(select ps.owner_id from public.user_private_spaces ps
                         where ps.owner_id=(select id from me)),
 'shared_space_id',(select p.space_id from pair p
                      where p.member_count=2),
 'legacy_space_id',(select m.space_id from membership m),
 'is_paired',coalesce((select p.member_count=2 from pair p),false),
 'content_routing_enabled',false
)
$fn$;
revoke all on function public.my_storage_scopes() from public,anon;
grant execute on function public.my_storage_scopes() to authenticated;
