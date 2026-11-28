-- 0326 (28 Nov 2026, D110 onwards): personal reminders can point at a finance
-- item (source_kind 'finance'), so payment reminders use the normal reminder
-- delivery: before the due day, and the day after it for auto-paid bills.
-- Finance reminders are always personal (the owner's own storage, A3/A4):
-- a couple reminder can never point at a finance item.
-- The reminder text carries the item name only, never an amount (A19).
-- QA first; Production at go-live.

alter table public.reminders drop constraint if exists reminders_source_kind_check;
alter table public.reminders add constraint reminders_source_kind_check
  check (source_kind = any (array['task','calendar','occasion','activity','trip','note','finance']));

-- Same function as before (live QA definition of 28 Nov 2026) plus the finance branch.
create or replace function private.reminder_validate_source()
returns trigger language plpgsql security definer set search_path to '' as $function$
declare allowed boolean:=false;
begin
 if new.source_kind is null then return new; end if;
 if new.private_space_id is not null then
   if new.private_space_id is distinct from new.created_by then
     raise exception 'Personal reminder owner mismatch' using errcode='42501';
   end if;
   if new.source_kind='task' then
    select exists(select 1 from public.tasks t where t.id=new.source_id
      and t.private_space_id=new.private_space_id and t.created_by=new.created_by
      and t.space_id is null and t.migrated_to_list is null) into allowed;
   elsif new.source_kind='calendar' then
    select exists(select 1 from public.space_events e where e.id=new.source_id
      and e.private_space_id=new.private_space_id and e.created_by=new.created_by
      and e.space_id is null and e.archived_at is null) into allowed;
   elsif new.source_kind='occasion' then
    select exists(select 1 from public.occasion_plans o where o.id=new.source_id
      and o.private_space_id=new.private_space_id and o.created_by=new.created_by
      and o.space_id is null and o.archived_at is null) into allowed;
   elsif new.source_kind='activity' then
    select exists(select 1 from public.activities a where a.id=new.source_id
      and a.private_space_id=new.private_space_id and a.created_by=new.created_by
      and a.space_id is null and a.archived_at is null) into allowed;
   elsif new.source_kind='trip' then
    select exists(select 1 from public.shared_trips t where t.id=new.source_id
      and t.private_space_id=new.private_space_id and t.created_by=new.created_by
      and t.space_id is null and t.archived_at is null) into allowed;
   elsif new.source_kind='note' then
    select exists(select 1 from public.notes n where n.id=new.source_id
      and n.private_space_id=new.private_space_id and n.created_by=new.created_by
      and n.space_id is null and n.archived_at is null) into allowed;
   elsif new.source_kind='finance' then
    select exists(select 1 from public.fin_items f where f.id=new.source_id
      and f.private_space_id=new.private_space_id and f.created_by=new.created_by
      and f.archived_at is null) into allowed;
   end if;
   if not allowed then
     raise exception 'A personal reminder can only link to your own personal items'
       using errcode='42501';
   end if;
   return new;
 end if;
 if new.source_kind='task' then
  select exists(select 1 from public.tasks t
   where t.id=new.source_id and t.space_id=new.space_id and t.migrated_to_list is null
    and (t.visibility='shared' or (new.visibility='private' and t.created_by=new.created_by))) into allowed;
 elsif new.source_kind='calendar' then
  select exists(select 1 from public.space_events e
   where e.id=new.source_id and e.space_id=new.space_id and e.archived_at is null
    and (e.visibility='shared' or (new.visibility='private' and e.created_by=new.created_by))) into allowed;
 elsif new.source_kind='occasion' then
  select exists(select 1 from public.occasion_plans o
   where o.id=new.source_id and o.space_id=new.space_id and o.archived_at is null
    and (o.visibility='shared' or (new.visibility='private' and o.created_by=new.created_by))) into allowed;
 elsif new.source_kind='activity' then
  select exists(select 1 from public.activities a
   where a.id=new.source_id and a.space_id=new.space_id and a.archived_at is null
    and (a.visibility='shared' or (new.visibility='private' and a.created_by=new.created_by))) into allowed;
 elsif new.source_kind='trip' then
  select exists(select 1 from public.shared_trips t
   where t.id=new.source_id and t.space_id=new.space_id and t.archived_at is null
    and (t.visibility='shared' or (new.visibility='private' and t.created_by=new.created_by))) into allowed;
 elsif new.source_kind='note' then
  select exists(select 1 from public.notes n
   where n.id=new.source_id and n.space_id=new.space_id and n.archived_at is null
    and (n.visibility='shared' or (new.visibility='private' and n.created_by=new.created_by))) into allowed;
 elsif new.source_kind='finance' then
  raise exception 'Finance reminders are personal' using errcode='42501';
 end if;
 if not allowed then
  raise exception 'Linked item unavailable or not visible to reminder recipients';
 end if;
 return new;
end $function$;

-- Archiving or deleting a finance item retires its reminder.
create or replace function private.fin_retire_reminders()
returns trigger language plpgsql security definer set search_path to '' as $f$
begin
  if tg_op = 'DELETE' then
    delete from public.reminders where source_kind = 'finance' and source_id = old.id
      and private_space_id = old.private_space_id;
    return old;
  end if;
  if new.archived_at is not null and old.archived_at is null then
    update public.reminders set archived_at = now()
      where source_kind = 'finance' and source_id = new.id
        and private_space_id = new.private_space_id and archived_at is null;
  end if;
  return new;
end $f$;
revoke all on function private.fin_retire_reminders() from public, anon, authenticated;
drop trigger if exists fin_retire_reminders on public.fin_items;
create trigger fin_retire_reminders after update or delete on public.fin_items
  for each row execute function private.fin_retire_reminders();
