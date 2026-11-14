-- R22 notifications compatibility: existing notification uniqueness is
-- recipient + kind + object; refresh a due reminder instead of duplicating.
alter table public.space_notifications
 drop constraint if exists space_notifications_object_kind_check;
alter table public.space_notifications
 add constraint space_notifications_object_kind_check check(
 object_kind in ('activity','letter','calendar','gesture','note','checkin',
 'checkin_request','experience','trip','occasion','task','reminder'));
-- Existing kind 'reminder' also represents calendar alerts; object_kind
-- disambiguates the separate R22 Remember Reminders workflow.
create or replace function private.dispatch_due_reminders(p_at timestamptz default now())
returns integer language plpgsql security definer set search_path='' as $$
declare item record; dispatched integer:=0;
begin
 for item in
  select rr.id,rr.recipient_id,rr.next_alert_at,r.id reminder_id,
   r.space_id,r.created_by,r.title
  from public.reminder_recipients rr
  join public.reminders r on r.id=rr.reminder_id
  where rr.state in ('pending','follow_up') and rr.next_alert_at<=p_at
   and rr.next_alert_at is not null and r.archived_at is null
   and rr.last_notified_at is distinct from rr.next_alert_at
   and exists(select 1 from public.space_members m
    where m.space_id=r.space_id and m.user_id=rr.recipient_id)
  order by rr.next_alert_at limit 100 for update of rr skip locked
 loop
  insert into public.space_notifications
   (space_id,recipient_id,actor_id,kind,object_kind,object_id,headline,
    generated_automatically)
   values(item.space_id,item.recipient_id,item.created_by,'reminder',
    'reminder',item.reminder_id,left('Reminder: '||item.title,180),true)
   on conflict(recipient_id,kind,object_id)
   do update set headline=excluded.headline,read_at=null,
     created_at=p_at,generated_automatically=true;
  update public.reminder_recipients rr set last_notified_at=item.next_alert_at,
    updated_at=p_at where rr.id=item.id;
  dispatched:=dispatched+1;
 end loop;
 return dispatched;
end $$;
revoke all on function private.dispatch_due_reminders(timestamptz)
 from public,anon,authenticated;
