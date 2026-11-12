-- Shared and private text memories, dated journal and full RLS.
create table public.memories (
  id uuid primary key default gen_random_uuid(),
  space_id uuid not null references public.spaces(id) on delete cascade,
  created_by uuid not null references auth.users(id),
  title text not null check (char_length(btrim(title)) between 1 and 120),
  body text not null default '' check (char_length(body) <= 20000),
  memory_date date not null check (memory_date between date '1900-01-01' and date '2100-12-31'),
  visibility text not null default 'shared' check (visibility in ('shared','private')),
  pinned boolean not null default false,
  archived_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index memories_by_space_date on public.memories(space_id,memory_date desc);
create index memories_by_owner on public.memories(space_id,created_by)
  where visibility='private';
create trigger memories_updated_at before update on public.memories
 for each row execute function private.touch_note_updated_at();
alter table public.memories enable row level security;

alter table public.object_shares drop constraint object_shares_object_type_check;
alter table public.object_shares add constraint object_shares_object_type_check
 check (object_type in ('task','list','note','event','memory'));

create policy "Visible memories" on public.memories for select to authenticated
 using (private.is_space_member(space_id)
  and (visibility='shared' or created_by=(select auth.uid())
  or private.has_object_view_grant('memory',id,space_id)));
create policy "Create memory in my space" on public.memories for insert to authenticated
 with check (created_by=(select auth.uid()) and private.is_space_member(space_id));
create policy "Edit collaborative or own memory" on public.memories for update to authenticated
 using (private.is_space_member(space_id)
  and (visibility='shared' or created_by=(select auth.uid())))
 with check (private.is_space_member(space_id)
  and (visibility='shared' or created_by=(select auth.uid())));
revoke all on public.memories from public,anon,authenticated;
grant select on public.memories to authenticated;
grant insert(space_id,created_by,title,body,memory_date,visibility,pinned)
  on public.memories to authenticated;
grant update(title,body,memory_date,pinned,archived_at)
  on public.memories to authenticated;

create or replace function private.set_object_share(
 p_type text,p_object uuid,p_active boolean
) returns boolean language plpgsql security definer set search_path=''
as $$
declare
  v_owner uuid := auth.uid();
  v_space uuid;
  v_partner uuid;
begin
  if v_owner is null or p_type not in ('task','list','note','event','memory')
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
  elsif p_type='event' then
    select e.space_id into v_space from public.space_events e
      where e.id=p_object and e.created_by=v_owner and e.visibility='private';
  elsif p_type='memory' then
    select m.space_id into v_space from public.memories m
      where m.id=p_object and m.created_by=v_owner and m.visibility='private';
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
  if v_partner is null then raise exception 'No partner is connected'; end if;
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


create or replace function public.get_home_snapshot()
returns jsonb language sql stable security invoker set search_path=''
as $$
select jsonb_build_object(
 'space_id',s.id,
 'space_name',s.name,
 'member_count', (select count(*)::int from public.space_members m
                   where m.space_id=s.id),
 'members', (select coalesce(jsonb_agg(jsonb_build_object(
     'name',coalesce(p.display_name,'Member'),
     'is_me',m.user_id=(select auth.uid())
   ) order by m.joined_at),'[]'::jsonb)
   from public.space_members m left join public.profiles p on p.id=m.user_id
   where m.space_id=s.id),
 'pending_invitation_expires_at',
   (select i.expires_at from public.space_invitations i
     where i.space_id=s.id and i.invited_by=(select auth.uid())
       and i.revoked_at is null and i.accepted_at is null
       and i.expires_at > now() order by i.created_at desc limit 1),
 'open_shared_tasks', (select count(*)::int from public.tasks t
   where t.space_id=s.id and t.visibility='shared' and t.status='open'),
 'assigned_to_me', (select count(*)::int from public.tasks t
   where t.space_id=s.id and t.visibility='shared' and t.status='open'
     and t.assigned_to=(select auth.uid())),
 'my_private_tasks', (select count(*)::int from public.tasks t
   where t.space_id=s.id and t.visibility='private' and t.status='open'
     and t.created_by=(select auth.uid())),
 'completed_shared_tasks', (select count(*)::int from public.tasks t
   where t.space_id=s.id and t.visibility='shared' and t.status='completed'),
 'shopping_lists', (select count(*)::int from public.lists l
   where l.space_id=s.id and l.kind='shopping' and l.archived_at is null),
 'other_lists', (select count(*)::int from public.lists l
   where l.space_id=s.id and l.kind='checklist' and l.archived_at is null),
 'notes', (select count(*)::int from public.notes n
   where n.space_id=s.id and n.archived_at is null),
 'memories_count', (select count(*)::int from public.memories m
   where m.space_id=s.id and m.archived_at is null),
 'calendar_entries', (select count(*)::int from public.space_events e
   where e.space_id=s.id and e.archived_at is null)
)
from public.space_members own
join public.spaces s on s.id=own.space_id
where own.user_id=(select auth.uid())
limit 1;
$$;

alter publication supabase_realtime add table public.memories;
