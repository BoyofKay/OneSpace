-- R22: reject dangling cross-module references and private-parent
-- references attached to a shared reminder.
create function private.reminder_validate_source()
returns trigger language plpgsql security definer set search_path='' as $$
declare allowed boolean:=false;
begin
 if new.source_kind is null then return new; end if;
 if new.source_kind='task' then
  select exists(select 1 from public.tasks t
   where t.id=new.source_id and t.space_id=new.space_id
    and t.migrated_to_list is null
    and (t.visibility='shared' or
      (new.visibility='private' and t.created_by=new.created_by))) into allowed;
 elsif new.source_kind='calendar' then
  select exists(select 1 from public.space_events e
   where e.id=new.source_id and e.space_id=new.space_id
    and e.archived_at is null and
     (e.visibility='shared' or
       (new.visibility='private' and e.created_by=new.created_by))) into allowed;
 elsif new.source_kind='occasion' then
  select exists(select 1 from public.occasion_plans o
   where o.id=new.source_id and o.space_id=new.space_id
    and o.archived_at is null and
     (o.visibility='shared' or
       (new.visibility='private' and o.created_by=new.created_by))) into allowed;
 end if;
 if not allowed then
  raise exception 'Linked item unavailable or not visible to reminder recipients';
 end if;
 return new;
end $$;
create trigger reminder_validate_source_before_insert
 before insert on public.reminders for each row
 execute function private.reminder_validate_source();
revoke all on function private.reminder_validate_source()
 from public,anon,authenticated;
