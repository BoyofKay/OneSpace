-- R21: per-person, per-cycle checklist completion and searchable memory photo tags.
alter table public.task_checklist_checks
 add column if not exists task_id uuid references public.tasks(id) on delete cascade;
update public.task_checklist_checks c set task_id=i.task_id
 from public.task_checklist_items i where c.item_id=i.id and c.task_id is distinct from i.task_id;
alter table public.task_checklist_checks alter column task_id set not null;
create or replace function private.checklist_check_parent()
 returns trigger language plpgsql set search_path='' as $$
begin
 select task_id into new.task_id from public.task_checklist_items where id=new.item_id;
 if new.task_id is null then raise exception 'Checklist item not found'; end if;
 return new;
end $$;
drop trigger if exists checklist_check_parent on public.task_checklist_checks;
create trigger checklist_check_parent before insert on public.task_checklist_checks
 for each row execute function private.checklist_check_parent();
alter table public.task_checklist_checks drop constraint if exists task_checklist_checks_item_id_cycle_date_key;
alter table public.task_checklist_checks add constraint task_checklist_checks_item_cycle_person
 unique(item_id,cycle_date,user_id);
create index if not exists task_checklist_checks_task_cycle
 on public.task_checklist_checks(task_id,cycle_date,user_id);
drop policy if exists "Create checklist check on editable list" on public.task_checklist_checks;
create policy "Create own checklist check when assigned" on public.task_checklist_checks
 for insert to authenticated with check (
 user_id=(select auth.uid()) and exists (
 select 1 from public.task_checklist_items i join public.tasks t on t.id=i.task_id
 where i.id=item_id and t.id=task_id and t.migrated_to_list is null
 and (t.visibility='shared' or t.created_by=(select auth.uid()))
 and (t.assigned_to is null or t.assigned_to=(select auth.uid()))));
drop policy if exists "Update check on editable list" on public.task_checklist_checks;
create policy "Update only own checklist check" on public.task_checklist_checks
 for update to authenticated using (
 user_id=(select auth.uid()) and exists (
 select 1 from public.task_checklist_items i join public.tasks t on t.id=i.task_id
 where i.id=item_id and t.id=task_id
 and (t.visibility='shared' or t.created_by=(select auth.uid()))
 and (t.assigned_to is null or t.assigned_to=(select auth.uid()))))
 with check (
 user_id=(select auth.uid()) and exists (
 select 1 from public.task_checklist_items i join public.tasks t on t.id=i.task_id
 where i.id=item_id and t.id=task_id
 and (t.visibility='shared' or t.created_by=(select auth.uid()))
 and (t.assigned_to is null or t.assigned_to=(select auth.uid()))));
alter table public.memory_photos add column if not exists people_tags text[] not null default '{}'::text[];
alter table public.memory_photos add column if not exists place_tag text not null default '';
alter table public.memory_photos add column if not exists other_tags text[] not null default '{}'::text[];
alter table public.memory_photos add constraint photo_tags_length check (
 cardinality(people_tags)<=20 and cardinality(other_tags)<=30
 and char_length(place_tag)<=160
 and char_length(array_to_string(people_tags,','))<=1200
 and char_length(array_to_string(other_tags,','))<=1200);
grant update(people_tags,place_tag,other_tags) on public.memory_photos to authenticated;
create index if not exists memory_photos_people_tags on public.memory_photos using gin(people_tags);
create index if not exists memory_photos_other_tags on public.memory_photos using gin(other_tags);
