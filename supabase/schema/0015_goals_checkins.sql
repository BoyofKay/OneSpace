-- OneSpace goals and daily check-ins: collaborative planning plus daily connection.
create table public.goals (
 id uuid primary key default gen_random_uuid(),
 space_id uuid not null references public.spaces(id) on delete cascade,
 created_by uuid not null references auth.users(id),
 title text not null check (length(btrim(title)) between 1 and 120),
 description text not null default '' check(length(description)<=3000),
 target_date date,
 progress int not null default 0 check(progress between 0 and 100),
 status text not null default 'active' check(status in ('active','paused','achieved')),
 visibility text not null default 'shared' check(visibility in ('shared','private')),
 archived_at timestamptz,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create index goals_space_status on public.goals(space_id,status,updated_at desc);
create trigger goals_touch before update on public.goals for each row
 execute function private.touch_task_updated_at();
alter table public.goals enable row level security;
create policy "Visible goals" on public.goals for select to authenticated using (
 private.is_space_member(space_id) and (
 visibility='shared' or created_by=(select auth.uid())
 or (visibility='private' and private.has_object_view_grant('goal',id,space_id))));
create policy "Create own goals" on public.goals for insert to authenticated
 with check(created_by=(select auth.uid()) and private.is_space_member(space_id));
create policy "Edit collaborative or own goals" on public.goals for update to authenticated
 using(private.is_space_member(space_id)
  and (visibility='shared' or created_by=(select auth.uid())))
 with check(private.is_space_member(space_id)
  and (visibility='shared' or created_by=(select auth.uid())));
revoke all on public.goals from public,anon,authenticated;
grant select on public.goals to authenticated;
grant insert(space_id,created_by,title,description,target_date,progress,status,visibility)
 on public.goals to authenticated;
grant update(title,description,target_date,progress,status,archived_at)
 on public.goals to authenticated;

create table public.daily_checkins (
 id uuid primary key default gen_random_uuid(),
 space_id uuid not null references public.spaces(id) on delete cascade,
 created_by uuid not null references auth.users(id),
 checkin_date date not null,
 mood smallint not null check(mood between 1 and 5),
 message text not null default '' check(length(message)<=2000),
 gratitude text not null default '' check(length(gratitude)<=500),
 visibility text not null default 'shared' check(visibility in ('shared','private')),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(created_by,checkin_date)
);
create index daily_checkins_space_date on public.daily_checkins(space_id,checkin_date desc);
create trigger checkins_touch before update on public.daily_checkins for each row
 execute function private.touch_task_updated_at();
alter table public.daily_checkins enable row level security;
create policy "Visible checkins" on public.daily_checkins for select to authenticated using (
 private.is_space_member(space_id) and (
 visibility='shared' or created_by=(select auth.uid())
 or (visibility='private' and private.has_object_view_grant('checkin',id,space_id))));
create policy "Create my daily checkin" on public.daily_checkins for insert to authenticated
 with check(created_by=(select auth.uid()) and private.is_space_member(space_id));
create policy "Edit only my checkin" on public.daily_checkins for update to authenticated
 using(created_by=(select auth.uid()) and private.is_space_member(space_id))
 with check(created_by=(select auth.uid()) and private.is_space_member(space_id));
revoke all on public.daily_checkins from public,anon,authenticated;
grant select on public.daily_checkins to authenticated;
grant insert(space_id,created_by,checkin_date,mood,message,gratitude,visibility)
 on public.daily_checkins to authenticated;
grant update(mood,message,gratitude) on public.daily_checkins to authenticated;

alter table public.object_shares drop constraint object_shares_object_type_check;
alter table public.object_shares add constraint object_shares_object_type_check
 check (object_type in ('task','list','note','event','memory','goal','checkin'));

create or replace function private.set_object_share(
 p_type text,p_object uuid,p_active boolean
) returns boolean language plpgsql security definer set search_path=''
as $$
declare v_owner uuid := auth.uid(); v_space uuid; v_partner uuid;
begin
 if v_owner is null or p_type not in
  ('task','list','note','event','memory','goal','checkin')
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
 elsif p_type='goal' then
  select g.space_id into v_space from public.goals g
   where g.id=p_object and g.created_by=v_owner and g.visibility='private';
 elsif p_type='checkin' then
  select c.space_id into v_space from public.daily_checkins c
   where c.id=p_object and c.created_by=v_owner and c.visibility='private';
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
 on conflict(object_type,object_id,shared_with)
 do update set revoked_at=null
 where public.object_shares.shared_by=v_owner
  and public.object_shares.space_id=v_space;
 return true;
end;
$$;

alter publication supabase_realtime add table public.goals;
alter publication supabase_realtime add table public.daily_checkins;
