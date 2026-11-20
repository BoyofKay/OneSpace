-- QA two-scope Items-to-sort. Account-private text/links only until
-- personal Storage and attachment deletion are proven. Pair files unchanged.
drop policy if exists "QA read only current personal/pair sort inbox" on public.items_to_sort;
create policy "QA read only current personal/pair sort inbox" on public.items_to_sort
 as restrictive for select to authenticated
 using(
  (private_space_id=(select auth.uid()) and created_by=(select auth.uid())
    and visibility='private' and space_id is null)
   or
  (private_space_id is null and space_id is not null
    and private.is_space_member(space_id)
    and (visibility='shared' or created_by=(select auth.uid())))
 );
drop policy if exists "QA owner inserts private inbox text" on public.items_to_sort;
create policy "QA owner inserts private inbox text" on public.items_to_sort
 for insert to authenticated
 with check(private_space_id=(select auth.uid()) and created_by=(select auth.uid())
   and visibility='private' and space_id is null and file_path is null
   and file_name is null and file_mime is null and file_size is null);
drop policy if exists "QA owner updates private inbox text" on public.items_to_sort;
create policy "QA owner updates private inbox text" on public.items_to_sort
 for update to authenticated
 using(private_space_id=(select auth.uid()) and created_by=(select auth.uid())
  and visibility='private' and space_id is null)
 with check(private_space_id=(select auth.uid()) and created_by=(select auth.uid())
  and visibility='private' and space_id is null and file_path is null
  and file_name is null and file_mime is null and file_size is null);
drop policy if exists "QA current pair creates shared inbox item" on public.items_to_sort;
create policy "QA current pair creates shared inbox item" on public.items_to_sort
 as restrictive for insert to authenticated
 with check(visibility<>'shared' or
   (space_id is not null and private_space_id is null
    and private.is_space_member(space_id)
    and (select count(*) from public.space_members m where m.space_id=items_to_sort.space_id)=2));
drop policy if exists "QA current pair updates shared inbox item" on public.items_to_sort;
create policy "QA current pair updates shared inbox item" on public.items_to_sort
 as restrictive for update to authenticated
 using(
   (private_space_id=(select auth.uid()) and created_by=(select auth.uid())
    and space_id is null) or
   (private_space_id is null and space_id is not null and private.is_space_member(space_id))
 )
 with check(visibility<>'shared' or
   (space_id is not null and private_space_id is null
    and private.is_space_member(space_id)
    and (select count(*) from public.space_members m where m.space_id=items_to_sort.space_id)=2));

create or replace function private.qa_sort_inbox_scope_guard()
returns trigger language plpgsql set search_path=''
as $fn$
begin
 if current_user in ('authenticated','anon') then
   if tg_op='UPDATE' and
     (old.space_id is distinct from new.space_id
       or old.private_space_id is distinct from new.private_space_id
       or old.created_by is distinct from new.created_by
       or old.visibility is distinct from new.visibility
       or old.file_path is distinct from new.file_path
       or old.file_name is distinct from new.file_name
       or old.file_mime is distinct from new.file_mime
       or old.file_size is distinct from new.file_size) then
      raise exception 'Inbox ownership, privacy and attachment cannot be changed in place'
        using errcode='42501';
   end if;
   if tg_op='INSERT' and new.visibility='private' and
      (new.private_space_id is distinct from auth.uid()
       or new.created_by is distinct from auth.uid()
       or new.space_id is not null) then
      raise exception 'Update your app to save personal inbox items securely'
        using errcode='42501';
   end if;
   if new.private_space_id is not null and
     (new.private_space_id is distinct from auth.uid()
      or new.space_id is not null or new.created_by is distinct from auth.uid()
      or new.visibility<>'private' or new.file_path is not null
      or new.file_name is not null or new.file_mime is not null
      or new.file_size is not null) then
      raise exception 'Account-owned file storage is not enabled for inbox items'
        using errcode='42501';
   end if;
 end if;
 return new;
end $fn$;
revoke all on function private.qa_sort_inbox_scope_guard() from public,anon,authenticated;
drop trigger if exists qa_sort_inbox_scope_guard on public.items_to_sort;
create trigger qa_sort_inbox_scope_guard before insert or update on public.items_to_sort
 for each row execute function private.qa_sort_inbox_scope_guard();

drop policy if exists "QA owner reads private inbox action audit" on public.record_action_history;
create policy "QA owner reads private inbox action audit" on public.record_action_history
 for select to authenticated
 using(record_kind='sort_item' and private_space_id=(select auth.uid())
   and exists(select 1 from public.items_to_sort i where i.id=record_id
     and i.private_space_id=(select auth.uid()) and i.created_by=(select auth.uid())
     and i.visibility='private' and i.space_id is null));
grant select,insert,update on public.items_to_sort to authenticated;
