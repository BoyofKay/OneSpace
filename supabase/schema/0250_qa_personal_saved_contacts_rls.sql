-- Reconciled 2026-11-20: applied to QA (ugwrpeduzyzrujkizqfo) on 2026-11-20 from
-- qa/activities-memories-two-scope-cutover-20261120:supabase/schema/0243_qa_personal_saved_contacts_rls.sql (original number 0243). Kept verbatim so the
-- repository replays to the live QA schema. QA only; never apply to Production.
-- QA: Direct contact cards belong either to an account or to a current couple.
-- This does not migrate old private cards. No change is applied to Production.
-- The linked-Activity contact rows inherit Activity authorization separately.

drop policy if exists "QA account owner reads personal saved contacts" on public.saved_contacts;
create policy "QA account owner reads personal saved contacts"
 on public.saved_contacts for select to authenticated
 using(private_space_id=(select auth.uid()) and created_by=(select auth.uid())
   and visibility='private' and space_id is null);

drop policy if exists "QA account owner creates personal saved contacts" on public.saved_contacts;
create policy "QA account owner creates personal saved contacts"
 on public.saved_contacts for insert to authenticated
 with check(private_space_id=(select auth.uid()) and created_by=(select auth.uid())
   and visibility='private' and space_id is null);

drop policy if exists "QA account owner edits personal saved contacts" on public.saved_contacts;
create policy "QA account owner edits personal saved contacts"
 on public.saved_contacts for update to authenticated
 using(private_space_id=(select auth.uid()) and created_by=(select auth.uid())
   and visibility='private' and space_id is null)
 with check(private_space_id=(select auth.uid()) and created_by=(select auth.uid())
   and visibility='private' and space_id is null);

drop policy if exists "QA current pair creates shared saved contacts" on public.saved_contacts;
create policy "QA current pair creates shared saved contacts" on public.saved_contacts
 as restrictive for insert to authenticated
 with check(visibility<>'shared' or (space_id is not null
   and private.is_space_member(space_id)
   and (select count(*) from public.space_members sm
       where sm.space_id=saved_contacts.space_id)=2));

drop policy if exists "QA current pair edits shared saved contacts" on public.saved_contacts;
create policy "QA current pair edits shared saved contacts" on public.saved_contacts
 as restrictive for update to authenticated using(true)
 with check(visibility<>'shared' or (space_id is not null
   and private.is_space_member(space_id)
   and (select count(*) from public.space_members sm
       where sm.space_id=saved_contacts.space_id)=2));

-- Prevent any client from silently changing scope/author or turning a current
-- pair's contact into personal content (or exposing a private contact).
create or replace function private.qa_lock_saved_contact_scope()
returns trigger language plpgsql set search_path = ''
as $fn$
begin
 if current_user in ('authenticated','anon') and
    (old.space_id is distinct from new.space_id or
     old.private_space_id is distinct from new.private_space_id or
     old.created_by is distinct from new.created_by or
     old.visibility is distinct from new.visibility) then
     raise exception 'Changing contact ownership or visibility is not permitted'
       using errcode='42501';
 end if;
 return new;
end $fn$;
revoke all on function private.qa_lock_saved_contact_scope()
 from public,anon,authenticated;
drop trigger if exists qa_lock_saved_contact_scope on public.saved_contacts;
create trigger qa_lock_saved_contact_scope before update on public.saved_contacts
 for each row execute function private.qa_lock_saved_contact_scope();

-- Owner-only history follows the currently accessible parent even when unpaired.
drop policy if exists "QA owner reads personal contact action audit" on public.record_action_history;
create policy "QA owner reads personal contact action audit"
 on public.record_action_history for select to authenticated
 using(record_kind='contact' and private_space_id=(select auth.uid())
 and exists(select 1 from public.saved_contacts c where c.id=record_id
   and c.private_space_id=(select auth.uid())
   and c.created_by=(select auth.uid()) and c.visibility='private'));

grant select,insert,update on public.saved_contacts to authenticated;
