-- Reconciled 2026-11-20: applied to QA (ugwrpeduzyzrujkizqfo) on 2026-11-20 from
-- feat/personal-space-lifecycle:supabase/schema/0238_qa_personal_space_rows.sql (original number 0238). Kept verbatim so the
-- repository replays to the live QA schema. QA only; never apply to Production.
-- QA 0238: every account owns a personal space; private records live there.
--
-- Founder decision (20 Nov 2026): each person has (a) their own private space
-- and (b) a shared space with one specific partner. The app shows both as one.
--
-- Implementation: the personal space is a row in public.spaces with
-- personal_owner = the account. It never has space_members rows, so every
-- existing "my partner / my couple" lookup keeps working unchanged. Content
-- tables keep using space_id; RLS keeps using private.is_space_member(), which
-- now also accepts the owner of a personal space. Child tables have no
-- space_id and follow their parent, so they move with it.
--
-- A routing trigger puts every Private record in its creator's personal space
-- and every Shared record in the creator's couple space. Ending a couple can
-- then delete the couple space (and all shared content, by cascade) without
-- touching anyone's private records.
--
-- Notes, To-do, Reminders and Calendar already store private records with
-- private_space_id (0230-0237) and are left as they are.

alter table public.spaces
  add column if not exists personal_owner uuid references auth.users(id) on delete cascade;
create unique index if not exists spaces_one_personal_space_per_account
  on public.spaces(personal_owner) where personal_owner is not null;
comment on column public.spaces.personal_owner is
  'Set only on an account''s personal space. Personal spaces never have members or invitations.';

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------
create or replace function private.ensure_personal_space(p_user uuid)
returns uuid language plpgsql security definer set search_path=''
as $fn$
declare v uuid;
begin
  if p_user is null then return null; end if;
  select id into v from public.spaces where personal_owner=p_user;
  if v is null then
    insert into public.spaces(name,created_by,personal_owner)
    values('My space',p_user,p_user)
    on conflict do nothing
    returning id into v;
    if v is null then
      select id into v from public.spaces where personal_owner=p_user;
    end if;
  end if;
  return v;
end
$fn$;
revoke all on function private.ensure_personal_space(uuid) from public,anon,authenticated;

create or replace function private.couple_space_id(p_user uuid)
returns uuid language sql stable security definer set search_path=''
as $fn$
  select sm.space_id
  from public.space_members sm
  join public.spaces s on s.id=sm.space_id
  where sm.user_id=p_user and s.personal_owner is null
  order by sm.joined_at desc
  limit 1
$fn$;
revoke all on function private.couple_space_id(uuid) from public,anon,authenticated;

-- RLS helper used by almost every content policy: a member of a couple space,
-- or the owner of a personal space.
create or replace function private.is_space_member(p_space_id uuid)
returns boolean language sql stable security definer set search_path=''
as $fn$
  select exists (
    select 1 from public.space_members
    where space_id=p_space_id and user_id=(select auth.uid())
  ) or exists (
    select 1 from public.spaces
    where id=p_space_id and personal_owner=(select auth.uid())
  );
$fn$;

-- Same idea for a named user (assignees, travellers, "for" person).
create or replace function private.user_in_space(p_space_id uuid, p_user uuid)
returns boolean language sql stable security definer set search_path=''
as $fn$
  select exists (
    select 1 from public.space_members where space_id=p_space_id and user_id=p_user
  ) or exists (
    select 1 from public.spaces where id=p_space_id and personal_owner=p_user
  );
$fn$;
revoke all on function private.user_in_space(uuid,uuid) from public,anon;

create or replace function private.activity_for_user_is_member()
returns trigger language plpgsql security definer set search_path=''
as $fn$
begin
  if new.for_user_id is not null
     and not private.user_in_space(new.space_id,new.for_user_id) then
    raise exception 'That person is not in this space';
  end if;
  return new;
end $fn$;

create or replace function private.trip_check_traveler()
returns trigger language plpgsql security definer set search_path=''
as $fn$
begin
  if new.traveler_id is not null
     and not private.user_in_space(new.space_id,new.traveler_id) then
    raise exception 'The traveler must be a member of this space';
  end if;
  return new;
end $fn$;

-- ---------------------------------------------------------------------------
-- A personal space can never gain a member or an invitation.
-- ---------------------------------------------------------------------------
create or replace function private.reject_personal_space_sharing()
returns trigger language plpgsql security definer set search_path=''
as $fn$
begin
  if exists(select 1 from public.spaces
            where id=new.space_id and personal_owner is not null) then
    raise exception 'A personal space cannot be shared' using errcode='42501';
  end if;
  return new;
end $fn$;
revoke all on function private.reject_personal_space_sharing() from public,anon,authenticated;

drop trigger if exists personal_space_has_no_members on public.space_members;
create trigger personal_space_has_no_members
before insert or update of space_id on public.space_members
for each row execute function private.reject_personal_space_sharing();

drop trigger if exists personal_space_has_no_invitations on public.space_invitations;
create trigger personal_space_has_no_invitations
before insert or update of space_id on public.space_invitations
for each row execute function private.reject_personal_space_sharing();

-- ---------------------------------------------------------------------------
-- Every account gets its personal space at sign-up (and existing ones now).
-- ---------------------------------------------------------------------------
create or replace function private.create_private_space_for_new_user()
returns trigger language plpgsql security definer set search_path=''
as $fn$
begin
  if new.id is null then raise exception 'New user ID required'; end if;
  insert into public.user_private_spaces(owner_id) values(new.id)
  on conflict(owner_id) do nothing;
  perform private.ensure_personal_space(new.id);
  return new;
end
$fn$;

select private.ensure_personal_space(u.id)
from auth.users u where u.deleted_at is null;

-- One call for the app: which spaces does this account read and write?
create or replace function public.my_spaces()
returns jsonb language plpgsql security definer set search_path=''
as $fn$
declare v_me uuid:=auth.uid(); v_personal uuid; v_couple uuid; v_members int;
begin
  if v_me is null then raise exception 'Sign in first' using errcode='42501'; end if;
  v_personal:=private.ensure_personal_space(v_me);
  v_couple:=private.couple_space_id(v_me);
  select count(*) into v_members from public.space_members where space_id=v_couple;
  return jsonb_build_object(
    'personal_space_id',v_personal,
    'couple_space_id',v_couple,
    'member_count',coalesce(v_members,0),
    'is_paired',coalesce(v_members,0)=2);
end
$fn$;
revoke all on function public.my_spaces() from public,anon;
grant execute on function public.my_spaces() to authenticated;

-- ---------------------------------------------------------------------------
-- Routing: Private -> creator's personal space; Shared -> creator's couple.
-- Runs last among BEFORE triggers (name starts with zz) so table guards that
-- pin space_id on update have already run. RLS WITH CHECK runs after it.
-- ---------------------------------------------------------------------------
create or replace function private.route_record_scope()
returns trigger language plpgsql security definer set search_path=''
as $fn$
declare
  v_me uuid:=auth.uid();
  v_target uuid;
  v_couple uuid;
  v_personal_target boolean;
begin
  -- System jobs (cron, service role) and private_space_id rows are untouched.
  if v_me is null or new.space_id is null then return new; end if;
  if tg_op='UPDATE'
     and new.visibility is not distinct from old.visibility
     and new.space_id is not distinct from old.space_id then
    return new;
  end if;

  if new.visibility='private' then
    if tg_op='UPDATE' and old.created_by is distinct from v_me then
      raise exception 'Only the person who created this can make it private'
        using errcode='42501';
    end if;
    if new.created_by is distinct from v_me then
      raise exception 'Private records belong to the person who creates them'
        using errcode='42501';
    end if;
    v_target:=private.ensure_personal_space(v_me);
  else
    select s.personal_owner is not null into v_personal_target
    from public.spaces s where s.id=new.space_id;
    if coalesce(v_personal_target,false) then
      v_couple:=private.couple_space_id(v_me);
      if v_couple is null then
        -- Nobody to share with yet: it stays in this person's space.
        new.visibility:='private';
        v_target:=new.space_id;
      else
        v_target:=v_couple;
      end if;
    else
      v_target:=new.space_id;
    end if;
  end if;

  if v_target is distinct from new.space_id then
    new.space_id:=v_target;
    -- A person named on the record must be able to see it in its new place.
    if tg_table_name='activities' then
      if new.for_user_id is not null
         and not private.user_in_space(v_target,new.for_user_id) then
        new.for_user_id:=null;
      end if;
    elsif tg_table_name='shared_trips' then
      if new.traveler_id is not null
         and not private.user_in_space(v_target,new.traveler_id) then
        new.traveler_id:=null;
      end if;
    end if;
  end if;
  return new;
end
$fn$;
revoke all on function private.route_record_scope() from public,anon,authenticated;

do $routes$
declare t text;
begin
  foreach t in array array['activities','daily_checkins','goals','items_to_sort',
    'memories','occasion_plans','places','saved_contacts','shared_trips',
    'space_counters'] loop
    execute format('drop trigger if exists zz_route_record_scope on public.%I',t);
    execute format('create trigger zz_route_record_scope before insert or update on public.%I '
      'for each row execute function private.route_record_scope()',t);
  end loop;
end $routes$;

-- A visit is stored with its place (runs before the same-space guard).
create or replace function private.route_place_visit()
returns trigger language plpgsql security definer set search_path=''
as $fn$
declare v uuid;
begin
  select space_id into v from public.places where id=new.place_id;
  if v is not null then new.space_id:=v; end if;
  return new;
end $fn$;
revoke all on function private.route_place_visit() from public,anon,authenticated;
drop trigger if exists a_route_place_visit on public.place_visits;
create trigger a_route_place_visit before insert or update of place_id, space_id
on public.place_visits for each row execute function private.route_place_visit();

-- ---------------------------------------------------------------------------
-- Retire the abandoned archive "vault" mirrors (no archiving, ADR 20 Nov).
-- They also reject personal-space rows ("owner must be a space member").
-- ---------------------------------------------------------------------------
do $vault$
declare r record;
begin
  for r in
    select t.tgrelid::regclass as tbl, t.tgname
    from pg_trigger t join pg_proc p on p.oid=t.tgfoid
    where not t.tgisinternal
      and p.proname in ('mirror_personal_vault_record','tombstone_personal_vault_record',
        'mirror_personal_vault_dependent','tombstone_personal_vault_dependent',
        'qa_mirror_trip_child','qa_trip_children_on_parent_change',
        'qa_mirror_private_task_child','mirror_personal_days_off')
  loop
    execute format('drop trigger if exists %I on %s',r.tgname,r.tbl);
  end loop;
end $vault$;
