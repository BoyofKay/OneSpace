-- QA: First account-owned Calendar event cutover. Private events survive
-- relationship changes without any membership/FK dependence. Legacy events
-- remain untouched and Production schema is not changed.
CREATE OR REPLACE FUNCTION private.validate_event_person()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
 if new.private_space_id is not null then
   if new.space_id is not null or new.created_by is distinct from new.private_space_id
     or new.visibility<>'private'
     or (new.for_user_id is not null and new.for_user_id is distinct from new.created_by) then
       raise exception 'Personal calendar event must belong to its account owner';
   end if;
   return new;
 end if;
 if new.for_user_id is not null and not exists(
    select 1 from public.space_members
    where space_id=new.space_id and user_id=new.for_user_id
 ) then raise exception 'The selected person is not part of this space'; end if;
 return new;
end; $function$
;

drop policy if exists "QA account owner reads personal events" on public.space_events;
create policy "QA account owner reads personal events" on public.space_events
 for select to authenticated using
 (private_space_id=(select auth.uid()) and created_by=(select auth.uid())
   and visibility='private' and space_id is null
   and (for_user_id is null or for_user_id=(select auth.uid())));
drop policy if exists "QA account owner creates personal events" on public.space_events;
create policy "QA account owner creates personal events" on public.space_events
 for insert to authenticated with check
 (private_space_id=(select auth.uid()) and created_by=(select auth.uid())
   and visibility='private' and space_id is null
   and (for_user_id is null or for_user_id=(select auth.uid())));
drop policy if exists "QA account owner edits personal events" on public.space_events;
create policy "QA account owner edits personal events" on public.space_events
 for update to authenticated
 using(private_space_id=(select auth.uid()) and created_by=(select auth.uid())
  and visibility='private' and space_id is null)
 with check(private_space_id=(select auth.uid()) and created_by=(select auth.uid())
  and visibility='private' and space_id is null
  and (for_user_id is null or for_user_id=(select auth.uid())));

drop policy if exists "QA current pair creates shared events" on public.space_events;
create policy "QA current pair creates shared events" on public.space_events
 as restrictive for insert to authenticated
 with check(visibility<>'shared' or
   (select count(*) from public.space_members m where m.space_id=space_events.space_id)=2);
drop policy if exists "QA current pair edits shared events" on public.space_events;
create policy "QA current pair edits shared events" on public.space_events
 as restrictive for update to authenticated using(true)
 with check(visibility<>'shared' or
   (select count(*) from public.space_members m where m.space_id=space_events.space_id)=2);

drop policy if exists "QA owner reads personal event audit" on public.record_action_history;
create policy "QA owner reads personal event audit" on public.record_action_history
 for select to authenticated using
 (record_kind='event' and private_space_id=(select auth.uid())
 and exists(select 1 from public.space_events e where e.id=record_id
   and e.private_space_id=(select auth.uid())
   and e.created_by=(select auth.uid()) and e.visibility='private'));

drop trigger if exists qa_lock_personal_scope on public.space_events;
create trigger qa_lock_personal_scope before update on public.space_events
 for each row execute function private.qa_lock_personal_root_scope();

grant insert,update on public.space_events to authenticated;
