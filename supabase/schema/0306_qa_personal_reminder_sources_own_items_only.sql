-- QA 0306: an account-owned reminder may point at one of the SAME account's
-- personal items (e.g. "Remind me" on a personal Activity), never at a couple's
-- shared item and never at someone else's item.
--
-- Before: every personal reminder with a source was refused, so "Remind me"
-- from a personal Activity, To-do, Calendar event, Occasion, Trip or Note failed.
-- Why only own personal items: a personal reminder survives a breakup, while a
-- shared source is erased with the couple; it would strand or leak the link.
-- Couple-scoped reminders keep their existing rules unchanged.
-- QA only; never apply to Production.

create or replace function private.reminder_validate_source()
returns trigger language plpgsql security definer set search_path to ''
as $function$
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
 end if;
 if not allowed then
  raise exception 'Linked item unavailable or not visible to reminder recipients';
 end if;
 return new;
end $function$;

-- The insert policy no longer forbids a source; the trigger above decides.
drop policy if exists "QA account owner creates private reminders" on public.reminders;
create policy "QA account owner creates private reminders" on public.reminders
 for insert to authenticated
 with check (private_space_id=(select auth.uid()) and created_by=(select auth.uid())
   and visibility='private' and audience='me' and space_id is null
   and ((source_kind is null and source_id is null)
        or (source_kind is not null and source_id is not null)));
