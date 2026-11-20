-- QA: Account-owned reminders independent of partner space (no archive).
-- Supports real due notifications and FCM for unpaired accounts, with owner-only RLS.
-- Existing relationship reminders remain valid; never mutate historical data.
alter table public.space_notifications alter column space_id drop not null;
alter table public.space_notifications
 add column if not exists private_space_id uuid references public.user_private_spaces(owner_id);
alter table public.space_notifications
 drop constraint if exists qa_notification_exactly_one_scope;
alter table public.space_notifications
 add constraint qa_notification_exactly_one_scope
 check ((space_id is not null) <> (private_space_id is not null)) not valid;
alter table public.space_notifications
 drop constraint if exists qa_private_notification_owner;
alter table public.space_notifications
 add constraint qa_private_notification_owner check(private_space_id is null or
 (private_space_id=recipient_id and recipient_id=actor_id and
  kind='reminder' and object_kind='reminder')) not valid;
create index if not exists qa_personal_notification_by_owner
 on public.space_notifications(private_space_id) where private_space_id is not null;
drop policy if exists "QA recipient sees account-owned reminders" on public.space_notifications;
create policy "QA recipient sees account-owned reminders" on public.space_notifications
 for select to authenticated using
 (private_space_id=(select auth.uid()) and recipient_id=(select auth.uid())
 and actor_id=(select auth.uid()) and space_id is null
 and kind='reminder' and object_kind='reminder');
drop policy if exists "QA recipient marks own personal reminder read" on public.space_notifications;
create policy "QA recipient marks own personal reminder read" on public.space_notifications
 for update to authenticated
 using(private_space_id=(select auth.uid()) and recipient_id=(select auth.uid())
  and actor_id=(select auth.uid()) and space_id is null)
 with check(private_space_id=(select auth.uid()) and recipient_id=(select auth.uid())
  and actor_id=(select auth.uid()) and space_id is null);

drop policy if exists "QA account owner sees private reminders" on public.reminders;
create policy "QA account owner sees private reminders" on public.reminders
 for select to authenticated
 using(private_space_id=(select auth.uid()) and created_by=(select auth.uid())
 and visibility='private' and audience='me' and space_id is null);
drop policy if exists "QA account owner creates private reminders" on public.reminders;
create policy "QA account owner creates private reminders" on public.reminders
 for insert to authenticated
 with check(private_space_id=(select auth.uid()) and created_by=(select auth.uid())
  and visibility='private' and audience='me' and space_id is null
  and source_kind is null and source_id is null);
drop policy if exists "QA account owner edits private reminders" on public.reminders;
create policy "QA account owner edits private reminders" on public.reminders
 for update to authenticated
 using(private_space_id=(select auth.uid()) and created_by=(select auth.uid())
  and visibility='private' and audience='me' and space_id is null)
 with check(private_space_id=(select auth.uid()) and created_by=(select auth.uid())
  and visibility='private' and audience='me' and space_id is null
  and source_kind is null and source_id is null);
drop policy if exists "QA shared reminders require pair insert" on public.reminders;
create policy "QA shared reminders require pair insert" on public.reminders as restrictive
 for insert to authenticated with check(visibility<>'shared' or
 (select count(*) from public.space_members m where m.space_id=reminders.space_id)=2);
drop policy if exists "QA shared reminders require pair update" on public.reminders;
create policy "QA shared reminders require pair update" on public.reminders as restrictive
 for update to authenticated using(true)
 with check(visibility<>'shared' or
 (select count(*) from public.space_members m where m.space_id=reminders.space_id)=2);
alter table public.reminders drop constraint if exists qa_private_reminder_audience;
alter table public.reminders add constraint qa_private_reminder_audience
 check(private_space_id is null or
  (audience='me' and visibility='private' and
   source_kind is null and source_id is null and urgent=false)) not valid;

drop policy if exists "QA private reminder recipient reads own state" on public.reminder_recipients;
create policy "QA private reminder recipient reads own state" on public.reminder_recipients
 for select to authenticated
 using(recipient_id=(select auth.uid()) and exists(
 select 1 from public.reminders r
 where r.id=reminder_id and r.private_space_id=(select auth.uid())
 and r.created_by=(select auth.uid()) and r.visibility='private'
 and r.audience='me' and r.space_id is null));
drop policy if exists "QA private reminder recipient reads own actions" on public.reminder_actions;
create policy "QA private reminder recipient reads own actions" on public.reminder_actions
 for select to authenticated
 using(recipient_id=(select auth.uid()) and exists(
 select 1 from public.reminders r
 where r.id=reminder_id and r.private_space_id=(select auth.uid())
 and r.created_by=(select auth.uid()) and r.visibility='private'
 and r.audience='me' and r.space_id is null));
drop policy if exists "QA owner sees personal reminder audit" on public.record_action_history;
create policy "QA owner sees personal reminder audit" on public.record_action_history
 for select to authenticated using
 (record_kind='reminder' and private_space_id=(select auth.uid())
 and exists(select 1 from public.reminders r where r.id=record_id
  and r.private_space_id=(select auth.uid())
  and r.created_by=(select auth.uid()) and r.visibility='private'));
grant insert,update on public.reminders to authenticated;
-- No authenticated write grants on recipient/action history or push outbox.
CREATE OR REPLACE FUNCTION private.dispatch_due_reminders(p_at timestamp with time zone DEFAULT now())
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare item record; dispatched integer:=0; quiet timestamptz; nxt timestamptz;
begin
 for item in
  select rr.id,rr.recipient_id,rr.next_alert_at,rr.open_occurrence_at,
   r.id reminder_id,r.space_id,r.private_space_id,r.created_by,r.title,r.urgent,r.repeat_rule,
   r.due_at,r.source_kind,r.source_id,r.source_closed_at
  from public.reminder_recipients rr
  join public.reminders r on r.id=rr.reminder_id
  where rr.state in ('pending','follow_up') and rr.next_alert_at<=p_at
   and rr.next_alert_at is not null and r.archived_at is null
   and rr.last_notified_at is distinct from rr.next_alert_at
   and (
     (r.private_space_id=rr.recipient_id and r.created_by=rr.recipient_id
       and r.space_id is null and r.visibility='private' and r.audience='me')
      or (r.private_space_id is null and exists(
       select 1 from public.space_members m
       where m.space_id=r.space_id and m.user_id=rr.recipient_id))
   )
  order by rr.next_alert_at limit 100 for update of rr skip locked
 loop
  if item.source_kind is not null
     and private.reminder_source_closed(item.source_kind,item.source_id) then
   update public.reminders set source_closed_at=coalesce(source_closed_at,p_at)
    where id=item.reminder_id;
   update public.reminder_recipients set next_alert_at=null,open_occurrence_at=null,
    updated_at=p_at where id=item.id;
   insert into public.reminder_actions(reminder_id,recipient_id,actor_id,action,note)
    values(item.reminder_id,item.recipient_id,null,'source_closed',
     'The linked item was completed, cancelled or removed.');
   continue;
  end if;
  if item.recipient_id<>item.created_by and not item.urgent then
   quiet:=private.reminder_quiet_until(item.recipient_id,p_at);
   if quiet is not null and quiet>item.next_alert_at then
    update public.reminder_recipients set next_alert_at=quiet,updated_at=p_at
     where id=item.id;
    insert into public.reminder_actions(reminder_id,recipient_id,actor_id,action,note,next_alert_at)
     values(item.reminder_id,item.recipient_id,null,'deferred',
      'Held during sleep hours; delivered at wake-up.',quiet);
    continue;
   end if;
  end if;
  if item.repeat_rule is not null and item.open_occurrence_at is not null then
   insert into public.reminder_actions(reminder_id,recipient_id,actor_id,action,note,next_alert_at)
    values(item.reminder_id,item.recipient_id,null,'missed','',item.open_occurrence_at);
  end if;
  insert into public.space_notifications
   (space_id,private_space_id,recipient_id,actor_id,kind,object_kind,object_id,headline,
    generated_automatically)
   values(item.space_id,item.private_space_id,item.recipient_id,item.created_by,'reminder',
    'reminder',item.reminder_id,
    left(case when item.urgent then 'Urgent: ' else 'Reminder: ' end||item.title,180),true)
   on conflict(recipient_id,kind,object_id)
   do update set headline=excluded.headline,read_at=null,
     created_at=p_at,generated_automatically=true;
  if item.repeat_rule is not null then
   nxt:=private.reminder_next_occurrence(item.repeat_rule,item.due_at,
     greatest(item.next_alert_at,p_at));
   update public.reminder_recipients rr set
     state='pending',open_occurrence_at=item.next_alert_at,
     last_notified_at=item.next_alert_at,next_alert_at=nxt,
     snoozed_until=null,updated_at=p_at
    where rr.id=item.id;
  else
   update public.reminder_recipients rr set last_notified_at=item.next_alert_at,
     updated_at=p_at where rr.id=item.id;
  end if;
  dispatched:=dispatched+1;
 end loop;
 return dispatched;
end $function$
;
CREATE OR REPLACE FUNCTION public.respond_to_reminder(p_reminder_id uuid, p_action text, p_note text DEFAULT ''::text, p_snooze_until timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare who uuid:=auth.uid(); rec record; note_text text:=btrim(coalesce(p_note,''));
begin
 if who is null or p_reminder_id is null then raise exception 'Sign in required'; end if;
 if p_action not in ('done','follow_up','snooze','reopen')
    or length(note_text)>1200 then raise exception 'Invalid reminder response'; end if;
 select rr.id,rr.state,rr.next_alert_at,rr.open_occurrence_at,
   r.space_id,r.private_space_id,r.created_by,r.visibility,r.archived_at,r.repeat_rule,r.due_at into rec
 from public.reminder_recipients rr join public.reminders r on r.id=rr.reminder_id
 where rr.reminder_id=p_reminder_id and rr.recipient_id=who
 for update of rr;
 if not found or rec.archived_at is not null or
   not ((rec.private_space_id=who and rec.created_by=who
     and rec.space_id is null and rec.visibility='private') or
    (rec.private_space_id is null and exists(select 1 from public.space_members m
     where m.space_id=rec.space_id and m.user_id=who))) then
   raise exception 'Reminder unavailable';
 end if;
 if p_action='follow_up' and note_text='' then
   raise exception 'Add an outcome note explaining the follow-up';
 end if;
 if p_action='snooze' and (p_snooze_until is null
   or p_snooze_until <= now()+interval '1 minute'
   or p_snooze_until > now()+interval '366 days') then
   raise exception 'Choose a future snooze date and time';
 end if;

 if rec.repeat_rule is not null then
  if p_action='done' then
   if rec.open_occurrence_at is null then
    if rec.next_alert_at is null or rec.next_alert_at>now()+interval '12 hours' then
     raise exception 'Nothing is due yet for this repeating reminder';
    end if;
    update public.reminder_recipients set state='pending',outcome_note=note_text,
     acknowledged_at=now(),
     next_alert_at=private.reminder_next_occurrence(rec.repeat_rule,rec.due_at,rec.next_alert_at),
     last_notified_at=null,snoozed_until=null,updated_at=now() where id=rec.id;
   else
    update public.reminder_recipients set state='pending',outcome_note=note_text,
     acknowledged_at=now(),open_occurrence_at=null,snoozed_until=null,
     updated_at=now() where id=rec.id;
   end if;
  elsif p_action='follow_up' then
   update public.reminder_recipients set outcome_note=note_text,acknowledged_at=now(),
    open_occurrence_at=null,updated_at=now() where id=rec.id;
  elsif p_action='snooze' then
   update public.reminder_recipients set open_occurrence_at=null,
    outcome_note=case when note_text<>'' then note_text else outcome_note end,
    next_alert_at=p_snooze_until,snoozed_until=p_snooze_until,
    last_notified_at=null,updated_at=now() where id=rec.id;
  else
   update public.reminder_recipients set state='pending',acknowledged_at=null,
    next_alert_at=now(),snoozed_until=null,last_notified_at=null,
    updated_at=now() where id=rec.id;
  end if;
 elsif p_action='done' then
  update public.reminder_recipients set state='done',outcome_note=note_text,
   acknowledged_at=now(),next_alert_at=null,snoozed_until=null,
   updated_at=now() where id=rec.id;
 elsif p_action='follow_up' then
  update public.reminder_recipients set state='follow_up',
   outcome_note=note_text,acknowledged_at=now(),
   next_alert_at=now()+interval '1 day',snoozed_until=null,
   last_notified_at=null,updated_at=now() where id=rec.id;
 elsif p_action='snooze' then
  update public.reminder_recipients set state=case when state='done'
    then 'pending' else state end,
   outcome_note=case when note_text<>'' then note_text else outcome_note end,
   next_alert_at=p_snooze_until,snoozed_until=p_snooze_until,
   last_notified_at=null,updated_at=now() where id=rec.id;
 else
  update public.reminder_recipients set state='pending',acknowledged_at=null,
   next_alert_at=now(),snoozed_until=null,last_notified_at=null,
   updated_at=now() where id=rec.id;
 end if;
 insert into public.reminder_actions(reminder_id,recipient_id,actor_id,
   action,note,next_alert_at)
 select rr.reminder_id,rr.recipient_id,who,p_action,note_text,rr.next_alert_at
 from public.reminder_recipients rr where rr.id=rec.id;
end $function$
;
CREATE OR REPLACE FUNCTION public.claim_push_outbox(p_limit integer DEFAULT 25)
 RETURNS TABLE(delivery_id uuid, registration_token text, notification_id uuid, title text, body text, tag text, summary boolean)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 if auth.role() is distinct from 'service_role'
 then raise exception 'Backend service authorization required';end if;

 update private.push_outbox o set state='dead',lease_until=null,
   last_error='Read in the app before delivery'
 from public.space_notifications n
 where n.id=o.notification_id and o.state='pending' and n.read_at is not null;

 with held as(
   select o.id,o.device_record_id,
     row_number() over(partition by o.device_record_id order by n.created_at desc,o.id) rn,
     count(*) over(partition by o.device_record_id) cnt
   from private.push_outbox o
   join public.space_notifications n on n.id=o.notification_id
   where o.state='pending' and o.quiet_deferred and o.next_attempt_at<=now())
 update private.push_outbox o set
   state=case when h.rn>1 then 'sent' else o.state end,
   sent_at=case when h.rn>1 then now() else o.sent_at end,
   last_error=case when h.rn>1 then 'Folded into the wake-up summary' else o.last_error end,
   fold_count=case when h.rn=1 then h.cnt-1 else o.fold_count end
 from held h where h.id=o.id and h.cnt>1;

 return query
 with candidates as(
   select o.id from private.push_outbox o
   join public.push_devices d on d.id=o.device_record_id
   join public.space_notifications n on n.id=o.notification_id
   where o.state in ('pending','leased')
     and (o.state='pending' or o.lease_until<now())
     and o.next_attempt_at<=now() and o.attempts<8
     and d.enabled and n.recipient_id=d.user_id
     and (
       (n.private_space_id=n.recipient_id and n.space_id is null
        and n.actor_id=n.recipient_id and n.kind='reminder' and n.object_kind='reminder')
       or (n.private_space_id is null and exists(select 1 from public.space_members m
        where m.space_id=n.space_id and m.user_id=n.recipient_id))
     )
   order by o.next_attempt_at,o.created_at
   limit least(greatest(coalesce(p_limit,25),1),50)
   for update of o skip locked
 ),
 claimed as(
   update private.push_outbox o set state='leased',
      lease_until=now()+interval '3 minutes',attempts=o.attempts+1
   from candidates c where o.id=c.id
   returning o.id,o.device_record_id,o.notification_id,o.fold_count
 )
 select c.id,d.fcm_token,c.notification_id,
   case when c.fold_count>0 then
     case when coalesce(p.locale,'en')='ar' then 'أثناء نومك' else 'While you were asleep' end
     else coalesce(n.push_title,'OneSpace') end,
   case when c.fold_count>0 then
     (c.fold_count+1)::text||case when coalesce(p.locale,'en')='ar'
       then ' تحديثات · آخرها: ' else ' updates · latest: ' end||coalesce(n.push_title,'')
     else coalesce(n.push_body,'') end,
   case when c.fold_count>0 then 'summary' else n.kind||':'||n.object_id::text end,
   c.fold_count>0
 from claimed c
 join public.push_devices d on d.id=c.device_record_id
 join public.space_notifications n on n.id=c.notification_id
 left join public.profiles p on p.id=n.recipient_id;
end $function$
;
CREATE OR REPLACE FUNCTION private.queue_notification_push()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_due timestamptz; v_quiet timestamptz;
begin
 if tg_op='UPDATE' and not(
    new.created_at is distinct from old.created_at
   or (new.read_at is null and old.read_at is not null)) then
  return new;
 end if;
 if new.read_at is not null then return new; end if;
 v_due:=greatest(coalesce(new.push_due_at,new.created_at),now()-interval '1 minute');
 if new.actor_id<>new.recipient_id and new.kind<>'reminder' then
   v_quiet:=private.reminder_quiet_until(new.recipient_id,v_due);
 end if;
 insert into private.push_outbox(notification_id,device_record_id,event_at,
   next_attempt_at,quiet_deferred)
 select new.id,d.id,coalesce(v_quiet,v_due),coalesce(v_quiet,v_due),v_quiet is not null
 from public.push_devices d
 where d.user_id=new.recipient_id and d.enabled
 and (
   (new.private_space_id=new.recipient_id and new.space_id is null
    and new.actor_id=new.recipient_id and new.kind='reminder' and new.object_kind='reminder')
   or (new.private_space_id is null and exists(select 1 from public.space_members m
    where m.space_id=new.space_id and m.user_id=new.recipient_id))
 )
 on conflict(notification_id,device_record_id,event_at) do nothing;
 return new;
end $function$
;
CREATE OR REPLACE FUNCTION private.reminder_validate_source()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare allowed boolean:=false;
begin
 if new.source_kind is null then return new; end if;
 -- Personal reminders cannot point into another relationship's shared
 -- objects or even cross-reference a private child until the scoped
 -- linkage contract is separately verified.
 if new.private_space_id is not null then
   raise exception 'Account-owned reminders cannot yet link another item';
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
end $function$
;
