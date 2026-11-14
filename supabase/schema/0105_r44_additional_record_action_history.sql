-- R44: extend server-generated who/what/when history to four records.
-- Only field *names*, never private check-in text/contact details/documents.
-- Existing R40 history and all source-table RLS remain unchanged.
alter table public.record_action_history
 drop constraint record_action_history_record_kind_check;
alter table public.record_action_history
 add constraint record_action_history_record_kind_check
 check(record_kind in ('note','task','goal','memory','event','reminder',
  'occasion','experience','trip','contact','checkin','checkin_request'));

drop policy "Read history only through readable current records"
 on public.record_action_history;
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
  or (record_kind='trip' and exists(select 1 from public.shared_trips t
    where t.id=record_id and t.space_id=record_action_history.space_id))
  or (record_kind='contact' and exists(select 1 from public.saved_contacts c
    where c.id=record_id and c.space_id=record_action_history.space_id))
  or (record_kind='checkin' and exists(select 1 from public.daily_checkins d
    where d.id=record_id and d.space_id=record_action_history.space_id))
  or (record_kind='checkin_request' and exists(
    select 1 from public.partner_checkin_requests q
    where q.id=record_id and q.space_id=record_action_history.space_id))
 );

create or replace function private.audit_additional_record_action()
returns trigger language plpgsql security definer
set search_path='' as $$
declare
 kind text;
 before jsonb;
 after jsonb;
 fields text[];
 action_name text;
begin
 kind:=case tg_table_name
  when 'shared_trips' then 'trip'
  when 'saved_contacts' then 'contact'
  when 'daily_checkins' then 'checkin'
  when 'partner_checkin_requests' then 'checkin_request'
  else null end;
 if kind is null then raise exception 'Unsupported audited source';end if;
 after:=to_jsonb(new);
 if tg_op='INSERT' then
  action_name:='created';
  select coalesce(array_agg(key order by key),'{}'::text[]) into fields
  from jsonb_object_keys(after) as keys(key)
  where key not in ('updated_at','created_at','id','space_id','created_by');
 else
  before:=to_jsonb(old);
  select coalesce(array_agg(key order by key),'{}'::text[]) into fields
  from jsonb_object_keys(after) as keys(key)
  where (after->key) is distinct from (before->key)
   and key not in ('updated_at','created_at');
  if cardinality(fields)=0 then return new;end if;
  action_name:=case
   when before->>'archived_at' is null and
    after->>'archived_at' is not null then 'archived'
   when before->>'archived_at' is not null and
    after->>'archived_at' is null then 'restored'
   when kind='trip' and before->>'status'<>'cancelled'
    and after->>'status'='cancelled' then 'cancelled'
   when kind='trip' and before->>'status'='cancelled'
    and after->>'status'<>'cancelled' then 'reopened'
   else 'edited' end;
 end if;
 insert into public.record_action_history(
  space_id,record_kind,record_id,actor_id,action,changed_fields)
 values((after->>'space_id')::uuid,kind,(after->>'id')::uuid,
  auth.uid(),action_name,fields);
 return new;
end;
$$;
revoke all on function private.audit_additional_record_action()
 from public,anon,authenticated;

create trigger r44_trip_actions after insert or update
 on public.shared_trips for each row
 execute function private.audit_additional_record_action();
create trigger r44_contact_actions after insert or update
 on public.saved_contacts for each row
 execute function private.audit_additional_record_action();
create trigger r44_checkin_actions after insert or update
 on public.daily_checkins for each row
 execute function private.audit_additional_record_action();
create trigger r44_checkin_request_actions after insert or update
 on public.partner_checkin_requests for each row
 execute function private.audit_additional_record_action();
