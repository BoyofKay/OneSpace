-- R40: common, append-only who/what/when history for core records.
-- Existing feature-specific audit logs remain intact. We never copy private
-- body, content, passwords or media into the history.
create table if not exists public.record_action_history(
 id bigint generated always as identity primary key,
 space_id uuid not null references public.spaces(id) on delete cascade,
 record_kind text not null check (record_kind in (
  'note','task','goal','memory','event','reminder','occasion','experience')),
 record_id uuid not null,
 actor_id uuid references auth.users(id) on delete set null,
 action text not null check (action in (
  'created','edited','archived','restored','cancelled','reopened')),
 changed_fields text[] not null default '{}',
 happened_at timestamptz not null default clock_timestamp()
);
create index if not exists record_action_history_by_record
 on public.record_action_history(record_kind,record_id,happened_at desc);
alter table public.record_action_history enable row level security;
create policy "Read history only through readable current records"
 on public.record_action_history for select to authenticated
 using (
  (record_kind='note' and exists(select 1 from public.notes n
    where n.id=record_id and n.space_id=record_action_history.space_id))
  or (record_kind='task' and exists(select 1 from public.tasks t
    where t.id=record_id and t.space_id=record_action_history.space_id))
  or (record_kind='goal' and exists(select 1 from public.goals g
    where g.id=record_id and g.space_id=record_action_history.space_id))
  or (record_kind='memory' and exists(select 1 from public.memories m
    where m.id=record_id and m.space_id=record_action_history.space_id))
  or (record_kind='event' and exists(select 1 from public.space_events e
    where e.id=record_id and e.space_id=record_action_history.space_id))
  or (record_kind='reminder' and exists(select 1 from public.reminders r
    where r.id=record_id and r.space_id=record_action_history.space_id))
  or (record_kind='occasion' and exists(select 1 from public.occasion_plans p
    where p.id=record_id and p.space_id=record_action_history.space_id))
  or (record_kind='experience' and exists(
    select 1 from public.shared_experiences x
    where x.id=record_id and x.space_id=record_action_history.space_id))
 );
revoke all on public.record_action_history from public,anon,authenticated;
grant select on public.record_action_history to authenticated;

create or replace function private.capture_record_action()
returns trigger language plpgsql security definer
set search_path='' as $$
declare
 before jsonb;
 after jsonb;
 fields text[];
 action_name text;
 kind text;
begin
 kind:=case tg_table_name
  when 'notes' then 'note'
  when 'tasks' then 'task'
  when 'goals' then 'goal'
  when 'memories' then 'memory'
  when 'space_events' then 'event'
  when 'reminders' then 'reminder'
  when 'occasion_plans' then 'occasion'
  when 'shared_experiences' then 'experience'
  else null end;
 if kind is null then raise exception 'Unsupported audited table';end if;
 after:=to_jsonb(new);
 if tg_op='INSERT' then
  action_name:='created';
  select coalesce(array_agg(key order by key),'{}'::text[]) into fields
   from jsonb_object_keys(after) as k(key)
   where key not in ('updated_at','created_at','id','space_id','created_by');
 else
  before:=to_jsonb(old);
  select coalesce(array_agg(key order by key),'{}'::text[]) into fields
   from jsonb_object_keys(after) as k(key)
   where (after->key) is distinct from (before->key)
    and key not in ('updated_at','created_at');
  if cardinality(fields)=0 then return new;end if;
  action_name:=case
   when before->>'archived_at' is null and
    after->>'archived_at' is not null then 'archived'
   when before->>'archived_at' is not null and
    after->>'archived_at' is null then 'restored'
   when kind='task' and before->>'status'<>'cancelled' and
    after->>'status'='cancelled' then 'cancelled'
   when kind='task' and before->>'status'='cancelled' and
    after->>'status'<>'cancelled' then 'reopened'
   else 'edited' end;
 end if;
 insert into public.record_action_history(
  space_id,record_kind,record_id,actor_id,action,changed_fields)
 values ((after->>'space_id')::uuid,kind,(after->>'id')::uuid,
  auth.uid(),action_name,fields);
 return new;
end;
$$;
revoke all on function private.capture_record_action()
 from public,anon,authenticated;

create trigger r40_note_actions after insert or update
 on public.notes for each row execute function private.capture_record_action();
create trigger r40_task_actions after insert or update
 on public.tasks for each row execute function private.capture_record_action();
create trigger r40_goal_actions after insert or update
 on public.goals for each row execute function private.capture_record_action();
create trigger r40_memory_actions after insert or update
 on public.memories for each row execute function private.capture_record_action();
create trigger r40_event_actions after insert or update
 on public.space_events for each row execute function private.capture_record_action();
create trigger r40_reminder_actions after insert or update
 on public.reminders for each row execute function private.capture_record_action();
create trigger r40_occasion_actions after insert or update
 on public.occasion_plans for each row execute function private.capture_record_action();
create trigger r40_experience_actions after insert or update
 on public.shared_experiences for each row execute function private.capture_record_action();
