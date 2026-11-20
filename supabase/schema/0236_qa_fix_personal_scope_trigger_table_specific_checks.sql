-- QA hotfix: PostgreSQL composite trigger records are table-specific.
-- A reminder-only column cannot be referenced in an AND expression when
-- a Notes/Tasks trigger calls the same function.
create or replace function private.qa_lock_personal_root_scope()
returns trigger language plpgsql set search_path=''
as $fn$
begin
 if current_user in ('authenticated','anon') then
   if old.private_space_id is not null or new.private_space_id is not null then
     if old.private_space_id is distinct from new.private_space_id
       or old.space_id is distinct from new.space_id
       or old.created_by is distinct from new.created_by
       or old.visibility is distinct from new.visibility then
       raise exception 'Changing personal ownership or scope is not permitted';
     end if;
   end if;
   if tg_table_name='reminders' then
     if old.private_space_id is not null
       and (new.audience is distinct from old.audience or
            new.source_kind is distinct from old.source_kind or
            new.source_id is distinct from old.source_id) then
        raise exception 'Personal reminder audience and source are immutable';
     end if;
   end if;
 end if;
 return new;
end $fn$;
revoke all on function private.qa_lock_personal_root_scope()
 from public,anon,authenticated;
