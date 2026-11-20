-- QA: Prevent clients from switching the account/relationship ownership of
-- any saved Notes, Tasks or Reminders by editing raw root columns.
-- This protects the founder's one-object/one-scope invariant; safe server-side
-- data migration must run from privileged migration context and be audited.
create or replace function private.qa_lock_personal_root_scope()
returns trigger language plpgsql set search_path=''
as $fn$
begin
 if current_user in ('authenticated','anon')
 and (old.private_space_id is not null or new.private_space_id is not null)
 and (old.private_space_id is distinct from new.private_space_id
   or old.space_id is distinct from new.space_id
   or old.created_by is distinct from new.created_by
   or old.visibility is distinct from new.visibility) then
    raise exception 'Changing personal ownership or scope is not permitted';
 end if;
 if current_user in ('authenticated','anon') and tg_table_name='reminders'
 and old.private_space_id is not null
 and (new.audience is distinct from old.audience or
      new.source_kind is distinct from old.source_kind or
      new.source_id is distinct from old.source_id) then
    raise exception 'Personal reminder audience and source are immutable';
 end if;
 return new;
end $fn$;
revoke all on function private.qa_lock_personal_root_scope()
 from public,anon,authenticated;
drop trigger if exists qa_lock_personal_scope on public.notes;
create trigger qa_lock_personal_scope before update on public.notes
 for each row execute function private.qa_lock_personal_root_scope();
drop trigger if exists qa_lock_personal_scope on public.tasks;
create trigger qa_lock_personal_scope before update on public.tasks
 for each row execute function private.qa_lock_personal_root_scope();
drop trigger if exists qa_lock_personal_scope on public.reminders;
create trigger qa_lock_personal_scope before update on public.reminders
 for each row execute function private.qa_lock_personal_root_scope();

-- User interfaces only mark notifications read. Server-supplied headline,
-- recipient, scope and push fields must never be client-editable.
revoke update on public.space_notifications from authenticated;
grant update (read_at) on public.space_notifications to authenticated;
