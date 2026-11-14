-- R38 hardening: a view-only private-note share must not grant
-- permission to attach or detach references.
drop policy "Link only authorized notes and source objects"
 on public.note_references;
create policy "Link only editable notes and authorized sources"
 on public.note_references for insert to authenticated
 with check (
  created_by=(select auth.uid()) and
  exists(select 1 from public.notes n where n.id=note_id
   and n.archived_at is null and
   (n.visibility='shared' or n.created_by=(select auth.uid()))) and
  private.note_reference_visible(note_id,target_kind,target_id)
 );
drop policy "Unlink references from accessible notes"
 on public.note_references;
create policy "Unlink only from editable notes"
 on public.note_references for delete to authenticated
 using (exists(select 1 from public.notes n where n.id=note_id
  and n.archived_at is null and
  (n.visibility='shared' or n.created_by=(select auth.uid()))));
