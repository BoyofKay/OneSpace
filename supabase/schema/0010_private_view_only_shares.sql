-- OneSpace private-object sharing: only the creator grants/revokes view access
-- for the other CURRENT space member. Grants are read-only, never updates.
create table public.object_shares (
  id uuid primary key default gen_random_uuid(),
  space_id uuid not null references public.spaces(id) on delete cascade,
  object_type text not null check (object_type in ('task','list','note')),
  object_id uuid not null,
  shared_by uuid not null references auth.users(id),
  shared_with uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  revoked_at timestamptz,
  constraint object_shares_different_users check (shared_by <> shared_with),
  constraint object_shares_unique unique (object_type,object_id,shared_with)
);
create index object_shares_reader on public.object_shares
 (shared_with,space_id,object_type,object_id) where revoked_at is null;

alter table public.object_shares enable row level security;
create policy "Read only my sharing grants" on public.object_shares
 for select to authenticated
 using (shared_by = (select auth.uid()) or shared_with = (select auth.uid()));

revoke all on public.object_shares from public,anon,authenticated;
grant select on public.object_shares to authenticated;

-- SECURITY DEFINER is required to examine a grant without re-entering
-- RLS of the protected parent object. It only returns a boolean to RLS.
create or replace function private.has_object_view_grant(
 p_type text, p_object uuid, p_space uuid
) returns boolean language sql stable security definer set search_path=''
as $$
  select (select auth.uid()) is not null
  and private.is_space_member(p_space)
  and exists (
    select 1 from public.object_shares sh
    where sh.object_type=p_type and sh.object_id=p_object
      and sh.space_id=p_space
      and sh.shared_with=(select auth.uid())
      and sh.revoked_at is null
      and exists (select 1 from public.space_members member
        where member.space_id=p_space and member.user_id=sh.shared_by)
  );
$$;
revoke all on function private.has_object_view_grant(text,uuid,uuid)
 from public,anon,authenticated;
grant execute on function private.has_object_view_grant(text,uuid,uuid)
 to authenticated;

create or replace function private.set_object_share(
 p_type text,p_object uuid,p_active boolean
) returns boolean language plpgsql security definer set search_path=''
as $$
declare
  v_owner uuid := auth.uid();
  v_space uuid;
  v_partner uuid;
begin
  if v_owner is null or p_type not in ('task','list','note')
     or p_object is null or p_active is null then
    raise exception 'Invalid share request';
  end if;

  if p_type='task' then
    select t.space_id into v_space from public.tasks t
      where t.id=p_object and t.created_by=v_owner and t.visibility='private';
  elsif p_type='list' then
    select l.space_id into v_space from public.lists l
      where l.id=p_object and l.created_by=v_owner and l.visibility='private';
  elsif p_type='note' then
    select n.space_id into v_space from public.notes n
      where n.id=p_object and n.created_by=v_owner and n.visibility='private';
  end if;

  if v_space is null or not private.is_space_member(v_space) then
    raise exception 'Private item not found or not owned by you';
  end if;

  if not p_active then
    update public.object_shares sh set revoked_at=now()
      where sh.object_type=p_type and sh.object_id=p_object
        and sh.space_id=v_space and sh.shared_by=v_owner
        and sh.revoked_at is null;
    return false;
  end if;

  select m.user_id into v_partner from public.space_members m
    where m.space_id=v_space and m.user_id <> v_owner
    order by m.joined_at limit 1;
  if v_partner is null then
    raise exception 'No partner is connected';
  end if;

  insert into public.object_shares
    (space_id,object_type,object_id,shared_by,shared_with,revoked_at)
  values (v_space,p_type,p_object,v_owner,v_partner,null)
  on conflict (object_type,object_id,shared_with)
  do update set revoked_at=null
  where public.object_shares.shared_by=v_owner
    and public.object_shares.space_id=v_space;
  return true;
end;
$$;
revoke all on function private.set_object_share(text,uuid,boolean)
 from public,anon,authenticated;
grant execute on function private.set_object_share(text,uuid,boolean)
 to authenticated;

create or replace function public.set_object_share(
 p_type text,p_object uuid,p_active boolean
) returns boolean language sql security invoker set search_path=''
as $$ select private.set_object_share(p_type,p_object,p_active); $$;
revoke all on function public.set_object_share(text,uuid,boolean)
 from public,anon;
grant execute on function public.set_object_share(text,uuid,boolean)
 to authenticated;

drop policy "Read shared tasks or my private tasks" on public.tasks;
create policy "Read shared, own private or granted tasks"
 on public.tasks for select to authenticated
using (
 private.is_space_member(space_id) and
 (visibility='shared' or created_by=(select auth.uid())
  or (visibility='private'
    and private.has_object_view_grant('task',id,space_id)))
);

drop policy "Visible lists" on public.lists;
create policy "Read shared, own private or granted lists"
 on public.lists for select to authenticated
using (
 private.is_space_member(space_id) and
 (visibility='shared' or created_by=(select auth.uid())
  or (visibility='private'
    and private.has_object_view_grant('list',id,space_id)))
);

drop policy "Visible notes" on public.notes;
create policy "Read shared, own private or granted notes"
 on public.notes for select to authenticated
using (
 private.is_space_member(space_id) and
 (visibility='shared' or created_by=(select auth.uid())
  or (visibility='private'
    and private.has_object_view_grant('note',id,space_id)))
);

-- Critical: a share recipient may SELECT a parent list (and its items),
-- but MUST NOT create or modify its child rows.
drop policy "Add items to visible list" on public.list_items;
create policy "Add items to editable list"
 on public.list_items for insert to authenticated
with check (
 created_by=(select auth.uid())
 and exists (
   select 1 from public.lists parent where parent.id=list_id
    and parent.archived_at is null
    and (parent.visibility='shared' or parent.created_by=(select auth.uid()))
 )
);
drop policy "Edit visible list items" on public.list_items;
create policy "Edit items only in editable list"
 on public.list_items for update to authenticated
using (
 exists (
   select 1 from public.lists parent where parent.id=list_id
    and (parent.visibility='shared' or parent.created_by=(select auth.uid()))
 )
) with check (
 exists (
   select 1 from public.lists parent where parent.id=list_id
    and (parent.visibility='shared' or parent.created_by=(select auth.uid()))
 )
);

