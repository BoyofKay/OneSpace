-- Reconciled 2026-11-20: applied to QA (ugwrpeduzyzrujkizqfo) on 2026-11-20 from
-- qa/activities-memories-two-scope-cutover-20261120:supabase/schema/0247_qa_personal_places_and_visit_scopes.sql (original number 0247). Kept verbatim so the
-- repository replays to the live QA schema. QA only; never apply to Production.
-- QA only: places and their visits must share one account or current-couple scope.
-- Private photo/Memory linking and trip planning are withheld until Storage/Trips cutover.

drop policy if exists "QA owner reads personal places" on public.places;
create policy "QA owner reads personal places" on public.places
 for select to authenticated
 using(private_space_id=(select auth.uid()) and created_by=(select auth.uid())
   and visibility='private' and space_id is null);
drop policy if exists "QA owner inserts personal places" on public.places;
create policy "QA owner inserts personal places" on public.places
 for insert to authenticated
 with check(private_space_id=(select auth.uid()) and created_by=(select auth.uid())
   and visibility='private' and space_id is null);
drop policy if exists "QA owner updates personal places" on public.places;
create policy "QA owner updates personal places" on public.places
 for update to authenticated
 using(private_space_id=(select auth.uid()) and created_by=(select auth.uid())
   and visibility='private' and space_id is null)
 with check(private_space_id=(select auth.uid()) and created_by=(select auth.uid())
   and visibility='private' and space_id is null);
drop policy if exists "QA active pair creates shared places" on public.places;
create policy "QA active pair creates shared places" on public.places
 as restrictive for insert to authenticated
 with check(visibility<>'shared' or (space_id is not null and private_space_id is null
   and private.is_space_member(space_id)
   and (select count(*) from public.space_members m where m.space_id=places.space_id)=2));
drop policy if exists "QA active pair updates shared places" on public.places;
create policy "QA active pair updates shared places" on public.places
 as restrictive for update to authenticated using(true)
 with check(visibility<>'shared' or (space_id is not null and private_space_id is null
   and private.is_space_member(space_id)
   and (select count(*) from public.space_members m where m.space_id=places.space_id)=2));

create or replace function private.qa_place_scope_guard()
returns trigger language plpgsql set search_path=''
as $fn$
begin
 if current_user in ('authenticated','anon') then
   if tg_op='UPDATE' and (old.space_id is distinct from new.space_id
      or old.private_space_id is distinct from new.private_space_id
      or old.visibility is distinct from new.visibility
      or old.created_by is distinct from new.created_by) then
      raise exception 'Place scope and visibility cannot change in place'
        using errcode='42501';
   end if;
   if new.visibility='private' and tg_op='INSERT' and
     (new.private_space_id is distinct from auth.uid()
      or new.space_id is not null or new.created_by is distinct from auth.uid()) then
     raise exception 'Update your app to save private places securely'
       using errcode='42501';
   end if;
   if new.private_space_id is not null and
     (new.private_space_id is distinct from auth.uid()
      or new.created_by is distinct from auth.uid() or new.visibility<>'private'
      or new.space_id is not null or new.planned_trip_id is not null) then
     raise exception 'Personal place ownership or trip scope mismatch'
       using errcode='42501';
   end if;
 end if;
 return new;
end $fn$;
revoke all on function private.qa_place_scope_guard() from public,anon,authenticated;
drop trigger if exists qa_place_scope_guard on public.places;
create trigger qa_place_scope_guard before insert or update on public.places
 for each row execute function private.qa_place_scope_guard();

-- Child RLS: the author alone can mutate a visit, and only as a member of
-- the visit's live couple or as the owner of its account-scoped parent.
drop policy if exists "QA place visits follow readable parent" on public.place_visits;
create policy "QA place visits follow readable parent" on public.place_visits
 as restrictive for select to authenticated using(
  exists(select 1 from public.places p where p.id=place_visits.place_id
   and (
    (p.private_space_id=(select auth.uid()) and p.space_id is null
      and place_visits.private_space_id=p.private_space_id
      and place_visits.space_id is null) or
    (p.space_id is not null and p.private_space_id is null
      and place_visits.space_id=p.space_id and place_visits.private_space_id is null
      and private.is_space_member(p.space_id))
   )));
drop policy if exists "QA place visit parent insert scope" on public.place_visits;
create policy "QA place visit parent insert scope" on public.place_visits
 as restrictive for insert to authenticated
 with check(created_by=(select auth.uid()) and
   exists(select 1 from public.places p where p.id=place_visits.place_id
    and (
     (p.private_space_id=(select auth.uid()) and p.space_id is null
       and place_visits.private_space_id=p.private_space_id and place_visits.space_id is null) or
     (p.space_id is not null and p.private_space_id is null
       and place_visits.space_id=p.space_id and place_visits.private_space_id is null
       and private.is_space_member(p.space_id)
       and (select count(*) from public.space_members sm where sm.space_id=p.space_id)=2)
    )));
drop policy if exists "QA place visit parent update scope" on public.place_visits;
create policy "QA place visit parent update scope" on public.place_visits
 as restrictive for update to authenticated
 using(exists(select 1 from public.places p where p.id=place_visits.place_id
   and ((p.private_space_id=(select auth.uid()) and place_visits.private_space_id=p.private_space_id
         and place_visits.space_id is null) or
        (p.space_id=place_visits.space_id and p.private_space_id is null
         and place_visits.private_space_id is null and private.is_space_member(p.space_id)))))
 with check(created_by=(select auth.uid()) and
   exists(select 1 from public.places p where p.id=place_visits.place_id
   and ((p.private_space_id=(select auth.uid()) and place_visits.private_space_id=p.private_space_id
         and place_visits.space_id is null) or
        (p.space_id=place_visits.space_id and p.private_space_id is null
         and place_visits.private_space_id is null and private.is_space_member(p.space_id)))));
drop policy if exists "QA place visit parent delete scope" on public.place_visits;
create policy "QA place visit parent delete scope" on public.place_visits
 as restrictive for delete to authenticated
 using(exists(select 1 from public.places p where p.id=place_visits.place_id
   and ((p.private_space_id=(select auth.uid()) and place_visits.private_space_id=p.private_space_id
         and place_visits.space_id is null) or
        (p.space_id=place_visits.space_id and p.private_space_id is null
         and place_visits.private_space_id is null and private.is_space_member(p.space_id)))));

create or replace function private.qa_place_visit_scope_guard()
returns trigger language plpgsql set search_path=''
as $fn$
declare parent_record record;
begin
 if current_user not in ('authenticated','anon') then return new; end if;
 if tg_op='UPDATE' and
   (old.place_id is distinct from new.place_id
    or old.space_id is distinct from new.space_id
    or old.private_space_id is distinct from new.private_space_id
    or old.created_by is distinct from new.created_by) then
   raise exception 'Visit owner, place and scope are immutable'
     using errcode='42501';
 end if;
 select p.space_id,p.private_space_id,p.visibility into parent_record
 from public.places p where p.id=new.place_id;
 if not found then raise exception 'Place unavailable' using errcode='42501';end if;
 if new.created_by is distinct from auth.uid() then
   raise exception 'Visit must belong to signed-in author' using errcode='42501';end if;
 if parent_record.private_space_id is not null then
   if parent_record.private_space_id is distinct from auth.uid()
      or new.private_space_id is distinct from parent_record.private_space_id
      or new.space_id is not null then
     raise exception 'Personal visit must remain with its parent account'
       using errcode='42501';
   end if;
   if new.memory_id is not null then
     raise exception 'Private place photo/Memory linking is not enabled yet'
       using errcode='42501';
   end if;
 else
   if new.space_id is distinct from parent_record.space_id
      or new.private_space_id is not null
      or not private.is_space_member(parent_record.space_id) then
     raise exception 'Shared visit must stay with current couple'
       using errcode='42501';
   end if;
 end if;
 return new;
end $fn$;
revoke all on function private.qa_place_visit_scope_guard() from public,anon,authenticated;
drop trigger if exists qa_place_visit_scope_guard on public.place_visits;
create trigger qa_place_visit_scope_guard before insert or update on public.place_visits
 for each row execute function private.qa_place_visit_scope_guard();

grant select,insert,update on public.places to authenticated;
grant select,insert,update,delete on public.place_visits to authenticated;
