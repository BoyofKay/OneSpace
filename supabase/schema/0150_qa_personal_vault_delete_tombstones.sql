-- QA: do not resurrect deliberately deleted private content on later restore.
-- An eventual vetted relationship-retirement worker must SET LOCAL
-- onespace.retiring_space='on' before cascading old-space rows, preserving
-- owner-controlled vault snapshots across that specific transition.
alter table public.personal_vault_dependents
  add column if not exists restorable boolean not null default true;

create or replace function private.tombstone_personal_vault_record()
returns trigger language plpgsql security definer set search_path=''
as $$
declare uid uuid;
begin
 if current_setting('onespace.retiring_space',true)='on' then return old; end if;
 if tg_table_name='personal_days_off' then
   uid:=old.user_id;
 else
   if old.visibility is distinct from 'private' then return old; end if;
   uid:=old.created_by;
 end if;
 if uid is not null then
   update public.personal_vault_records set restorable=false,
     current_visibility='deleted',snapshot='{}'::jsonb,
     last_mirrored_at=now()
   where owner_id=uid and source_table=tg_table_name
     and source_id=old.id;
 end if;
 return old;
end $$;
revoke execute on function private.tombstone_personal_vault_record()
 from public,anon,authenticated;

do $$
declare tab text;
begin
 foreach tab in array array[
 'activities','daily_checkins','goals','items_to_sort','memories',
 'notes','occasion_plans','places','reminders','saved_contacts',
 'shared_trips','space_counters','space_events','tasks','personal_days_off']
 loop
   execute format('drop trigger if exists qa_personal_vault_delete on public.%I',tab);
   execute format('create trigger qa_personal_vault_delete after delete on public.%I
      for each row execute function private.tombstone_personal_vault_record()',tab);
 end loop;
end $$;

create or replace function private.tombstone_personal_vault_dependent()
returns trigger language plpgsql security definer set search_path=''
as $$
declare uid uuid;
begin
 if current_setting('onespace.retiring_space',true)='on' then return old; end if;
 if tg_table_name in
  ('occasion_budget_items','occasion_plan_steps','occasion_proposals')
 then uid:=old.created_by;
 elsif tg_table_name='reminder_recipients' then uid:=old.recipient_id;
 else raise exception 'Unrecognized private dependent'; end if;
 if uid is not null then
   update public.personal_vault_dependents set
     restorable=false,snapshot='{}'::jsonb,last_mirrored_at=now()
   where owner_id=uid and source_table=tg_table_name and source_id=old.id;
 end if;
 return old;
end $$;
revoke execute on function private.tombstone_personal_vault_dependent()
 from public,anon,authenticated;
do $$
declare tab text;
begin
 foreach tab in array array[
  'occasion_budget_items','occasion_plan_steps',
  'occasion_proposals','reminder_recipients']
 loop
  execute format('drop trigger if exists qa_personal_vault_dependent_delete on public.%I',tab);
  execute format('create trigger qa_personal_vault_dependent_delete after delete on public.%I
    for each row execute function private.tombstone_personal_vault_dependent()',tab);
 end loop;
end $$;
