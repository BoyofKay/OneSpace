-- QA: extend Personal Vault for inherently personal calendar days and
-- dependent child entries of PRIVATE parent records.
-- Non-private and other-partner child records must not be reclassified.

alter table public.personal_vault_records
 drop constraint if exists personal_vault_source_allowed;
alter table public.personal_vault_records
 add constraint personal_vault_source_allowed check(source_table in
 ('activities','daily_checkins','goals','items_to_sort','memories',
 'notes','occasion_plans','places','reminders','saved_contacts',
 'shared_trips','space_counters','space_events','tasks',
 'personal_days_off'));

insert into public.personal_vault_records(
 owner_id,source_table,source_id,source_space_id,
 original_visibility,current_visibility,restorable,snapshot)
select user_id,'personal_days_off',id,space_id,
 'private','private',true,to_jsonb(t)
from public.personal_days_off t where user_id is not null
on conflict(owner_id,source_table,source_id) do update set
 snapshot=excluded.snapshot, source_space_id=excluded.source_space_id,
 last_mirrored_at=now();

create or replace function private.mirror_personal_days_off()
returns trigger language plpgsql security definer set search_path=''
as $$
begin
 if new.user_id is null then return new; end if;
 insert into public.personal_vault_records(
 owner_id,source_table,source_id,source_space_id,
 original_visibility,current_visibility,restorable,snapshot)
 values(new.user_id,'personal_days_off',new.id,new.space_id,
 'private','private',true,to_jsonb(new))
 on conflict(owner_id,source_table,source_id) do update set
  snapshot=excluded.snapshot,source_space_id=excluded.source_space_id,
  last_mirrored_at=now();
 return new;
end $$;
revoke execute on function private.mirror_personal_days_off() from public,anon,authenticated;
drop trigger if exists qa_personal_days_off_mirror on public.personal_days_off;
create trigger qa_personal_days_off_mirror
after insert or update on public.personal_days_off for each row
execute function private.mirror_personal_days_off();

create table if not exists public.personal_vault_dependents(
 owner_id uuid not null references auth.users(id) on delete cascade,
 parent_table text not null,
 parent_id uuid not null,
 source_table text not null,
 source_id uuid not null,
 source_space_id uuid,
 snapshot jsonb not null,
 captured_at timestamptz not null default now(),
 last_mirrored_at timestamptz not null default now(),
 primary key(owner_id,source_table,source_id),
 constraint vault_child_type_allowed check(
 (parent_table='occasion_plans' and source_table in
  ('occasion_budget_items','occasion_plan_steps','occasion_proposals'))
 or (parent_table='reminders' and source_table='reminder_recipients'))
);
create index if not exists vault_dependents_parent_idx
 on public.personal_vault_dependents(owner_id,parent_table,parent_id);
alter table public.personal_vault_dependents enable row level security;
revoke all on public.personal_vault_dependents from public,anon,authenticated;

-- Private parent content is not blanket permission to copy another person's
-- child content; preserve only children actually created/received by owner.
insert into public.personal_vault_dependents
 (owner_id,parent_table,parent_id,source_table,source_id,source_space_id,snapshot)
select v.owner_id,'occasion_plans',v.source_id,'occasion_budget_items',
       child.id,v.source_space_id,to_jsonb(child)
from public.personal_vault_records v
join public.occasion_budget_items child
  on child.plan_id=v.source_id and child.created_by=v.owner_id
where v.source_table='occasion_plans' and v.restorable
on conflict(owner_id,source_table,source_id) do update
set snapshot=excluded.snapshot,last_mirrored_at=now();

insert into public.personal_vault_dependents
 (owner_id,parent_table,parent_id,source_table,source_id,source_space_id,snapshot)
select v.owner_id,'occasion_plans',v.source_id,'occasion_plan_steps',
       child.id,v.source_space_id,to_jsonb(child)
from public.personal_vault_records v
join public.occasion_plan_steps child
  on child.plan_id=v.source_id and child.created_by=v.owner_id
where v.source_table='occasion_plans' and v.restorable
on conflict(owner_id,source_table,source_id) do update
set snapshot=excluded.snapshot,last_mirrored_at=now();

insert into public.personal_vault_dependents
 (owner_id,parent_table,parent_id,source_table,source_id,source_space_id,snapshot)
select v.owner_id,'occasion_plans',v.source_id,'occasion_proposals',
       child.id,v.source_space_id,to_jsonb(child)
from public.personal_vault_records v
join public.occasion_proposals child
  on child.plan_id=v.source_id and child.created_by=v.owner_id
where v.source_table='occasion_plans' and v.restorable
on conflict(owner_id,source_table,source_id) do update
set snapshot=excluded.snapshot,last_mirrored_at=now();

insert into public.personal_vault_dependents
 (owner_id,parent_table,parent_id,source_table,source_id,source_space_id,snapshot)
select v.owner_id,'reminders',v.source_id,'reminder_recipients',
       child.id,v.source_space_id,to_jsonb(child)
from public.personal_vault_records v
join public.reminder_recipients child
  on child.reminder_id=v.source_id and child.recipient_id=v.owner_id
where v.source_table='reminders' and v.restorable
on conflict(owner_id,source_table,source_id) do update
set snapshot=excluded.snapshot,last_mirrored_at=now();

-- Mirroring after edits preserves owned dependencies while avoiding
-- unauthorized child changes in the vault (only matching parent+owner).
create or replace function private.mirror_personal_vault_dependent()
returns trigger language plpgsql security definer set search_path=''
as $$
declare owner uuid; parent_type text; parent_uuid uuid;
begin
 if tg_table_name in ('occasion_budget_items','occasion_plan_steps','occasion_proposals') then
    owner:=new.created_by; parent_type:='occasion_plans'; parent_uuid:=new.plan_id;
 elsif tg_table_name='reminder_recipients' then
    owner:=new.recipient_id; parent_type:='reminders'; parent_uuid:=new.reminder_id;
 else raise exception 'Unrecognized private child table'; end if;
 if owner is null then return new; end if;
 insert into public.personal_vault_dependents(
   owner_id,parent_table,parent_id,source_table,source_id,source_space_id,snapshot)
 select owner,parent_type,parent_uuid,tg_table_name,new.id,v.source_space_id,to_jsonb(new)
 from public.personal_vault_records v
 where v.owner_id=owner and v.source_table=parent_type
   and v.source_id=parent_uuid and v.restorable
 on conflict(owner_id,source_table,source_id) do update set
   snapshot=excluded.snapshot,last_mirrored_at=now();
 return new;
end $$;
revoke execute on function private.mirror_personal_vault_dependent()
 from public,anon,authenticated;
do $$
declare tab text;
begin
 foreach tab in array array[
  'occasion_budget_items','occasion_plan_steps',
  'occasion_proposals','reminder_recipients']
 loop
  execute format('drop trigger if exists qa_personal_vault_dependent on public.%I',tab);
  execute format('create trigger qa_personal_vault_dependent after insert or update on public.%I for each row execute function private.mirror_personal_vault_dependent()',tab);
 end loop;
end $$;
