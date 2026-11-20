-- Reconciled 2026-11-20: applied to QA (ugwrpeduzyzrujkizqfo) on 2026-11-20 from
-- qa/activities-memories-two-scope-cutover-20261120:supabase/schema/0245_qa_personal_days_off_owner_shared_scope.sql (original number 0245). Kept verbatim so the
-- repository replays to the live QA schema. QA only; never apply to Production.
-- QA: a day off is one record, in either personal account storage or a current couple.
-- Its scope cannot be switched in place by a client. No Production changes.
drop policy if exists "QA owner reads account days off" on public.personal_days_off;
create policy "QA owner reads account days off" on public.personal_days_off
 for select to authenticated
 using(private_space_id=(select auth.uid()) and user_id=(select auth.uid())
   and space_id is null);

drop policy if exists "QA owner creates account days off" on public.personal_days_off;
create policy "QA owner creates account days off" on public.personal_days_off
 for insert to authenticated
 with check(private_space_id=(select auth.uid()) and user_id=(select auth.uid())
   and space_id is null);

drop policy if exists "QA owner updates account days off" on public.personal_days_off;
create policy "QA owner updates account days off" on public.personal_days_off
 for update to authenticated
 using(private_space_id=(select auth.uid()) and user_id=(select auth.uid())
   and space_id is null)
 with check(private_space_id=(select auth.uid()) and user_id=(select auth.uid())
   and space_id is null);

drop policy if exists "QA owner deletes account days off" on public.personal_days_off;
create policy "QA owner deletes account days off" on public.personal_days_off
 for delete to authenticated
 using(private_space_id=(select auth.uid()) and user_id=(select auth.uid())
   and space_id is null);

-- Preserve paired visibility but never treat an unpaired/legacy solo space
-- as a destination for new shared day off rows.
drop policy if exists "QA account or active pair day off insert" on public.personal_days_off;
create policy "QA account or active pair day off insert" on public.personal_days_off
 as restrictive for insert to authenticated
 with check(
   user_id=(select auth.uid()) and (
    (private_space_id=(select auth.uid()) and space_id is null) or
    (private_space_id is null and space_id is not null
      and private.is_space_member(space_id)
      and (select count(*) from public.space_members m where m.space_id=personal_days_off.space_id)=2)
   )
 );

drop policy if exists "QA account or active pair day off update" on public.personal_days_off;
create policy "QA account or active pair day off update" on public.personal_days_off
 as restrictive for update to authenticated using(true)
 with check(
   user_id=(select auth.uid()) and (
    (private_space_id=(select auth.uid()) and space_id is null) or
    (private_space_id is null and space_id is not null
      and private.is_space_member(space_id)
      and (select count(*) from public.space_members m where m.space_id=personal_days_off.space_id)=2)
   )
 );

create or replace function private.qa_day_off_scope_guard()
returns trigger language plpgsql set search_path=''
as $fn$
begin
 if current_user in ('authenticated','anon') then
   if tg_op='UPDATE' and
     (new.private_space_id is distinct from old.private_space_id
       or new.space_id is distinct from old.space_id
       or new.user_id is distinct from old.user_id) then
     raise exception 'Changing a day-off owner or scope is not allowed'
       using errcode='42501';
   end if;
   if new.private_space_id is not null and
      (new.private_space_id is distinct from auth.uid()
       or new.user_id is distinct from auth.uid() or new.space_id is not null) then
     raise exception 'Personal day off must belong to the signed-in account'
       using errcode='42501';
   end if;
 end if;
 return new;
end $fn$;
revoke all on function private.qa_day_off_scope_guard() from public,anon,authenticated;
drop trigger if exists qa_day_off_scope_guard on public.personal_days_off;
create trigger qa_day_off_scope_guard before insert or update
 on public.personal_days_off for each row execute function private.qa_day_off_scope_guard();

grant select,insert,update,delete on public.personal_days_off to authenticated;
