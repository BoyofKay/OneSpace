-- Reconciled 2026-11-20: applied to QA (ugwrpeduzyzrujkizqfo) on 2026-11-20 from
-- qa/activities-memories-two-scope-cutover-20261120:supabase/schema/0244_qa_account_owned_daily_checkins.sql (original number 0244). Kept verbatim so the
-- repository replays to the live QA schema. QA only; never apply to Production.
-- QA only. Personal feelings stay with an account; partner check-in conversations stay couple scoped.
-- This creates no account deletion/relationship retirement capability.
create unique index if not exists qa_daily_checkins_personal_day_unique
 on public.daily_checkins(private_space_id, checkin_date) where private_space_id is not null;

drop policy if exists "QA owner reads personal daily checkins" on public.daily_checkins;
create policy "QA owner reads personal daily checkins" on public.daily_checkins
 for select to authenticated
 using(private_space_id=(select auth.uid()) and created_by=(select auth.uid())
   and visibility='private' and space_id is null);

drop policy if exists "QA owner creates personal daily checkins" on public.daily_checkins;
create policy "QA owner creates personal daily checkins" on public.daily_checkins
 for insert to authenticated
 with check(private_space_id=(select auth.uid()) and created_by=(select auth.uid())
   and visibility='private' and space_id is null);

drop policy if exists "QA owner edits personal daily checkins" on public.daily_checkins;
create policy "QA owner edits personal daily checkins" on public.daily_checkins
 for update to authenticated
 using(private_space_id=(select auth.uid()) and created_by=(select auth.uid())
   and visibility='private' and space_id is null)
 with check(private_space_id=(select auth.uid()) and created_by=(select auth.uid())
   and visibility='private' and space_id is null);

-- Restrictive policies apply to all INSERTs/UPDATEs in addition to
-- the existing permissive policies. Refuse 1-person 'shared' scopes.
drop policy if exists "QA paired shared daily checkins insert" on public.daily_checkins;
create policy "QA paired shared daily checkins insert" on public.daily_checkins
 as restrictive for insert to authenticated
 with check(visibility<>'shared' or
   (space_id is not null and private_space_id is null
    and private.is_space_member(space_id)
    and (select count(*) from public.space_members sm where sm.space_id=daily_checkins.space_id)=2));

drop policy if exists "QA paired shared daily checkins update" on public.daily_checkins;
create policy "QA paired shared daily checkins update" on public.daily_checkins
 as restrictive for update to authenticated using(true)
 with check(visibility<>'shared' or
   (space_id is not null and private_space_id is null
    and private.is_space_member(space_id)
    and (select count(*) from public.space_members sm where sm.space_id=daily_checkins.space_id)=2));

-- Stale QA Android clients must never be allowed to create private
-- check-ins in the old couple scope. Scope/visibility never mutate in place.
create or replace function private.qa_checkin_scope_guard()
returns trigger language plpgsql set search_path=''
as $fn$
begin
 if tg_op='UPDATE' and current_user in ('authenticated','anon')
    and (new.space_id is distinct from old.space_id
      or new.private_space_id is distinct from old.private_space_id
      or new.visibility is distinct from old.visibility
      or new.created_by is distinct from old.created_by) then
   raise exception 'Check-in ownership and visibility cannot be changed'
     using errcode='42501';
 end if;
 if tg_op='INSERT' and current_user in ('authenticated','anon') then
   if new.visibility='private' and
      (new.private_space_id is distinct from auth.uid()
       or new.space_id is not null or new.created_by is distinct from auth.uid()) then
     raise exception 'Update your app to save personal feelings securely'
       using errcode='42501';
   end if;
   if new.visibility='shared' and
      (new.private_space_id is not null or new.space_id is null) then
     raise exception 'Shared check-in needs an active couple'
       using errcode='42501';
   end if;
 end if;
 return new;
end $fn$;
revoke all on function private.qa_checkin_scope_guard()
 from public,anon,authenticated;
drop trigger if exists qa_checkin_scope_guard on public.daily_checkins;
create trigger qa_checkin_scope_guard before insert or update on public.daily_checkins
 for each row execute function private.qa_checkin_scope_guard();

drop policy if exists "QA owner reads personal checkin audit" on public.record_action_history;
create policy "QA owner reads personal checkin audit" on public.record_action_history
 for select to authenticated
 using(record_kind='checkin' and private_space_id=(select auth.uid())
   and exists(select 1 from public.daily_checkins c where c.id=record_id
     and c.private_space_id=(select auth.uid()) and c.created_by=(select auth.uid())
     and c.visibility='private' and c.space_id is null));

grant select,insert,update on public.daily_checkins to authenticated;
