-- QA only: Goals may be owned by an account or a current couple, never both.
-- The mobile Goals screen is not part of this migration; do not mark feature complete.
drop policy if exists "QA personal goals select" on public.goals;
create policy "QA personal goals select" on public.goals
 for select to authenticated
 using(private_space_id=(select auth.uid()) and created_by=(select auth.uid())
   and visibility='private' and space_id is null);
drop policy if exists "QA personal goals insert" on public.goals;
create policy "QA personal goals insert" on public.goals
 for insert to authenticated
 with check(private_space_id=(select auth.uid()) and created_by=(select auth.uid())
   and visibility='private' and space_id is null);
drop policy if exists "QA personal goals update" on public.goals;
create policy "QA personal goals update" on public.goals
 for update to authenticated
 using(private_space_id=(select auth.uid()) and created_by=(select auth.uid())
   and visibility='private' and space_id is null)
 with check(private_space_id=(select auth.uid()) and created_by=(select auth.uid())
   and visibility='private' and space_id is null);

drop policy if exists "QA current pair inserts shared goal" on public.goals;
create policy "QA current pair inserts shared goal" on public.goals
 as restrictive for insert to authenticated
 with check(visibility<>'shared' or
   (space_id is not null and private_space_id is null
     and private.is_space_member(space_id)
     and (select count(*) from public.space_members m where m.space_id=goals.space_id)=2));
drop policy if exists "QA current pair updates shared goal" on public.goals;
create policy "QA current pair updates shared goal" on public.goals
 as restrictive for update to authenticated using(true)
 with check(visibility<>'shared' or
   (space_id is not null and private_space_id is null
     and private.is_space_member(space_id)
     and (select count(*) from public.space_members m where m.space_id=goals.space_id)=2));

create or replace function private.qa_goal_scope_guard()
returns trigger language plpgsql set search_path=''
as $fn$
begin
 if current_user in ('authenticated','anon') then
   if tg_op='UPDATE' and
      (old.space_id is distinct from new.space_id
        or old.private_space_id is distinct from new.private_space_id
        or old.created_by is distinct from new.created_by
        or old.visibility is distinct from new.visibility) then
     raise exception 'Goal ownership or visibility cannot change in place'
       using errcode='42501';
   end if;
   if new.visibility='private' and
       (new.private_space_id is distinct from auth.uid() or new.space_id is not null
         or new.created_by is distinct from auth.uid()) and tg_op='INSERT' then
     raise exception 'Update your app to save personal goals securely'
       using errcode='42501';
   end if;
   if new.visibility='shared' and new.private_space_id is not null then
     raise exception 'Shared goals cannot use a private storage scope'
       using errcode='42501';
   end if;
 end if;
 return new;
end $fn$;
revoke all on function private.qa_goal_scope_guard() from public,anon,authenticated;
drop trigger if exists qa_goal_scope_guard on public.goals;
create trigger qa_goal_scope_guard before insert or update on public.goals
 for each row execute function private.qa_goal_scope_guard();

drop policy if exists "QA owner sees account goal history" on public.record_action_history;
create policy "QA owner sees account goal history" on public.record_action_history
 for select to authenticated
 using(record_kind='goal' and private_space_id=(select auth.uid())
   and exists(select 1 from public.goals g where g.id=record_id
     and g.private_space_id=(select auth.uid()) and g.created_by=(select auth.uid())
     and g.visibility='private' and g.space_id is null));
grant select,insert,update on public.goals to authenticated;
