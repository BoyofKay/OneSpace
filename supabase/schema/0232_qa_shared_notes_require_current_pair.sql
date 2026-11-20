-- QA 0232: sharing a Note requires an actual two-member relationship.
-- A user cannot create or transition a new Note into a singleton legacy space.
-- Historical personal notes in old singleton spaces remain editable during cutover.
drop policy if exists "Create note in my space" on public.notes;
create policy "Create note in my space"
on public.notes for insert to authenticated
with check (
 created_by=(select auth.uid())
 and private.is_space_member(space_id)
 and (visibility='private' or (
   visibility='shared' and
   (select count(*) from public.space_members members
     where members.space_id=notes.space_id)=2
 ))
);
drop policy if exists "QA current pair required to update shared note" on public.notes;
create policy "QA current pair required to update shared note"
on public.notes as restrictive for update to authenticated
using (true)
with check (visibility<>'shared'
  or (select count(*) from public.space_members members
       where members.space_id=notes.space_id)=2);
