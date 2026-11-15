-- OneSpace R48 - Notifications 2.0
-- Decisions: D5 (quiet hours), D6 (content push, recipient language),
-- D20 (chat batching: one push per item per 10 minutes, "+N more").
-- Spec: UX Redesign Specification v1, sections 5.1-5.4, backlog B-04..B-06.
--
-- Non-destructive: new nullable/defaulted columns, widened check constraints,
-- replaced functions and new triggers. No data is removed.
--
-- What changes
--  1. Every notification carries ready-made push text (push_title, push_body),
--     written in the recipient's app language (profiles.locale), using the
--     name the recipient calls their partner (profiles.partner_label) or the
--     partner's first name.
--  2. Plain Activity chat messages, trip messages and experience comments now
--     notify, collapsed to one feed row per item and at most one push per item
--     per 10 minutes; later messages join the next push as "+N more".
--  3. Meaningful changes to shared items notify (new to-do, Activity, memory,
--     reminder for you; date/time moved; status changed; assigned to you;
--     removed/restored). Wording and notes edits stay silent.
--  4. Pushes triggered by the partner wait for the recipient's wake-up time
--     (sleep window + days off, same rule as R47 reminders) and are folded into
--     one "While you were asleep" summary per device.
--  5. A push the recipient already read in the app is not sent.
--  6. claim_push_outbox returns the title, body and tray tag for the worker.

-- 1. Columns and constraints -------------------------------------------------
alter table public.space_notifications
  add column if not exists action text,
  add column if not exists detail text,
  add column if not exists push_title text,
  add column if not exists push_body text,
  add column if not exists push_due_at timestamptz,
  add column if not exists batch_count integer not null default 1,
  add column if not exists memory_id uuid references public.memories(id) on delete set null;

alter table public.space_notifications
  drop constraint if exists space_notifications_detail_check,
  add constraint space_notifications_detail_check
    check (detail is null or char_length(detail)<=400),
  drop constraint if exists space_notifications_batch_count_check,
  add constraint space_notifications_batch_count_check
    check (batch_count between 1 and 10000);

alter table public.space_notifications
  drop constraint if exists space_notifications_kind_check,
  add constraint space_notifications_kind_check check (kind = any (array[
    'mention','reply','letter','event','gesture','reminder','checkin_request',
    'checkin_response','checkin_shared','experience_suggestion','experience_comment',
    'trip_suggestion','trip_message','trip_document','occasion_shared','scrapbook_invite',
    'message','created','change']));

alter table public.space_notifications
  drop constraint if exists space_notifications_object_kind_check,
  add constraint space_notifications_object_kind_check check (object_kind = any (array[
    'activity','letter','calendar','gesture','note','checkin','checkin_request',
    'experience','trip','occasion','task','reminder','scrapbook','memory']));

alter table private.push_outbox
  add column if not exists quiet_deferred boolean not null default false,
  add column if not exists fold_count integer not null default 0;

comment on column public.space_notifications.push_title is
 'R48: push title in the recipient''s language, e.g. "Kay sent you a hug". Set by trigger.';
comment on column public.space_notifications.push_body is
 'R48: push body (the item title or message). Set by trigger.';
comment on column public.space_notifications.push_due_at is
 'R48: when the next push for this row is due (batching window for messages and changes).';
comment on column public.space_notifications.batch_count is
 'R48: how many messages/changes the due push covers ("+N more").';
comment on column private.push_outbox.quiet_deferred is
 'R48: held until the recipient''s wake-up time; folded into one summary per device.';

-- 2. Helpers -------------------------------------------------------------------
create or replace function private.notice_partner_name(p_recipient uuid, p_actor uuid)
returns text language sql stable security definer set search_path to '' as $$
 select coalesce(
   nullif(btrim((select r.partner_label from public.profiles r where r.id=p_recipient)),''),
   nullif(split_part(btrim(coalesce((select a.display_name from public.profiles a where a.id=p_actor),'')),' ',1),''),
   case when (select r.locale from public.profiles r where r.id=p_recipient)='ar'
     then 'شريكك' else 'Your partner' end)
$$;

create or replace function private.notice_when(p_recipient uuid, p_at timestamptz, p_day date)
returns text language sql stable security definer set search_path to '' as $$
 select case
  when p_at is not null then to_char(p_at at time zone coalesce(
     (select nullif(p.time_zone,'') from public.profiles p where p.id=p_recipient),'UTC'),
     'Dy DD Mon, FMHH12:MI AM')
  when p_day is not null then to_char(p_day,'Dy DD Mon')
  else null end
$$;

-- Plain item title from legacy headlines that carried a prefix.
create or replace function private.notice_bare_title(p_headline text)
returns text language sql immutable set search_path to '' as $$
 select regexp_replace(coalesce(p_headline,''),
  '^(New idea together: |Occasion plan: |Our next adventure: |Travel document shared: |New message on trip: |New thought on |Urgent: |Reminder: )','')
$$;

-- One place that writes a partner notice. Messages and changes collapse to one
-- row per item; p_window limits how often that row pushes.
create or replace function private.post_notice(
  p_space uuid, p_recipient uuid, p_actor uuid, p_kind text, p_object_kind text,
  p_object_id uuid, p_headline text, p_action text default null, p_detail text default null,
  p_window interval default interval '0',
  p_activity uuid default null, p_calendar uuid default null, p_experience uuid default null,
  p_trip uuid default null, p_occasion uuid default null, p_memory uuid default null)
returns void language plpgsql security definer set search_path to '' as $$
declare v_headline text:=left(coalesce(nullif(btrim(p_headline),''),'Untitled'),180);
begin
 if p_recipient is null or p_actor is null or p_recipient=p_actor then return; end if;
 if not exists(select 1 from public.space_members m
   where m.space_id=p_space and m.user_id=p_recipient) then return; end if;
 insert into public.space_notifications as n
  (space_id,recipient_id,actor_id,kind,object_kind,object_id,headline,action,detail,
   activity_id,calendar_event_id,experience_id,trip_id,occasion_id,memory_id,
   push_due_at,batch_count)
 values(p_space,p_recipient,p_actor,p_kind,p_object_kind,p_object_id,v_headline,
   p_action,left(p_detail,400),p_activity,p_calendar,p_experience,p_trip,p_occasion,p_memory,
   now(),1)
 on conflict (recipient_id,kind,object_id) do update set
   actor_id=excluded.actor_id, headline=excluded.headline, action=excluded.action,
   detail=excluded.detail, read_at=null, created_at=now(),
   push_due_at=case
     when n.push_due_at is null or now()>=n.push_due_at+p_window then now()
     when now()<n.push_due_at then n.push_due_at
     else n.push_due_at+p_window end,
   batch_count=case
     when n.push_due_at is null or now()>=n.push_due_at+p_window then 1
     when now()<n.push_due_at then least(n.batch_count+1,10000)
     else 1 end;
end $$;

-- 3. Push text, written for the recipient --------------------------------------
create or replace function private.compose_notification_text()
returns trigger language plpgsql security definer set search_path to '' as $$
declare
 ar boolean; who text; t text; b text; title text:=private.notice_bare_title(new.headline);
 g text; thing text; verb text;
begin
 -- Keep the push schedule in step for writers that only touch created_at.
 if tg_op='INSERT' then
   new.push_due_at:=coalesce(new.push_due_at,new.created_at,now());
 elsif new.created_at is distinct from old.created_at
   and new.push_due_at is not distinct from old.push_due_at then
   new.push_due_at:=new.created_at; new.batch_count:=1;
 end if;

 select coalesce(p.locale,'en')='ar' into ar from public.profiles p where p.id=new.recipient_id;
 ar:=coalesce(ar,false);
 who:=private.notice_partner_name(new.recipient_id,new.actor_id);

 if new.kind='gesture' then
   select pg.kind into g from public.partner_gestures pg where pg.id=new.object_id;
   t:=who||' '||case when ar then case g
       when 'hug' then 'أرسل لك حضنًا' when 'thinking' then 'يفكر فيك'
       when 'smile' then 'أرسل لك ابتسامة' when 'morning' then 'يقول صباح الخير'
       when 'goodnight' then 'يقول تصبح على خير' when 'proud' then 'فخور بك'
       when 'support' then 'معك' when 'thanks' then 'يشكرك'
       when 'lucky' then 'محظوظ بك' when 'miss_you' then 'يشتاق إليك'
       else 'أرسل لك لمسة حب' end
     else case g
       when 'hug' then 'sent you a hug' when 'thinking' then 'is thinking of you'
       when 'smile' then 'sent you a smile' when 'morning' then 'says good morning'
       when 'goodnight' then 'says good night' when 'proud' then 'is proud of you'
       when 'support' then 'is right here with you' when 'thanks' then 'says thank you'
       when 'lucky' then 'feels lucky to have you' when 'miss_you' then 'misses you'
       when 'miss_together' then 'misses being together' when 'miss_home' then 'misses home'
       when 'miss_kids' then 'misses the kids' when 'miss_pets' then 'misses the pets'
       else 'sent you a little love' end end;
   b:=new.headline;
 elsif new.kind='letter' then
   t:=who||case when ar then ' أرسل لك رسالة' else ' sent you a letter' end; b:=title;
 elsif new.kind='mention' then
   t:=who||case when ar then ' أشار إليك في ' else ' mentioned you in ' end||title;
   b:=coalesce(new.detail,title);
 elsif new.kind='reply' then
   t:=who||case when ar then ' ردّ عليك · ' else ' replied to you · ' end||title;
   b:=coalesce(new.detail,title);
 elsif new.kind in ('message','trip_message','experience_comment') then
   t:=who||' · '||title;
   b:=coalesce(new.detail,case when ar then 'رسالة جديدة' else 'New message' end);
 elsif new.kind='event' then
   t:=who||case when ar then ' أضاف موعدًا' else ' added an event' end;
   b:=title||coalesce(' · '||new.detail,'');
 elsif new.kind='trip_suggestion' then
   t:=who||case when ar then ' أضاف رحلة' else ' added a trip' end; b:=title;
 elsif new.kind='trip_document' then
   t:=who||case when ar then ' شارك مستند سفر' else ' shared a travel document' end; b:=title;
 elsif new.kind='occasion_shared' then
   t:=who||case when ar then ' خطط لمناسبة' else ' planned an occasion' end; b:=title;
 elsif new.kind='experience_suggestion' then
   t:=who||case when ar then ' اقترح تجربة' else ' suggested an experience' end; b:=title;
 elsif new.kind='checkin_request' then
   t:=who||case when ar then ' يطمئن عليك' else ' is checking in on you' end;
   b:=case when ar then 'اضغط للرد' else 'Tap to reply' end;
 elsif new.kind='checkin_response' then
   t:=who||case when ar then ' ردّ على اطمئنانك' else ' replied to your check-in' end;
   b:=case when ar then 'اضغط للقراءة' else 'Tap to read' end;
 elsif new.kind='checkin_shared' then
   t:=who||case when ar then ' شارك شعوره اليوم' else ' shared how they feel today' end;
   b:=case when ar then 'اضغط للقراءة' else 'Tap to read' end;
 elsif new.kind='scrapbook_invite' then
   t:=who||case when ar then ' دعاك إلى ألبوم' else ' invited you to a scrapbook' end;
   b:=case when ar then 'اضغط للفتح' else 'Tap to open' end;
 elsif new.kind='reminder' and new.object_kind='calendar' then
   t:=who||case when ar then ' يذكّرك بموعد' else ' reminds you about an event' end; b:=title;
 elsif new.kind='reminder' then
   if new.actor_id=new.recipient_id then
     t:=case when new.headline like 'Urgent: %' then case when ar then 'تذكير عاجل' else 'Urgent reminder' end
       else case when ar then 'تذكير' else 'Reminder' end end;
   else
     t:=case when new.headline like 'Urgent: %' then case when ar then 'تذكير عاجل من ' else 'Urgent reminder from ' end
       else case when ar then 'تذكير من ' else 'Reminder from ' end end||who;
   end if;
   b:=title;
 elsif new.kind='created' then
   thing:=case new.object_kind
     when 'task' then case when ar then 'مهمة' else 'a to-do' end
     when 'activity' then case when ar then 'نشاطًا' else 'an Activity' end
     when 'memory' then case when ar then 'ذكرى' else 'a memory' end
     when 'scrapbook' then case when ar then 'ذكرى' else 'a memory' end
     when 'reminder' then case when ar then 'تذكيرًا لك' else 'a reminder for you' end
     when 'calendar' then case when ar then 'موعدًا' else 'an event' end
     when 'trip' then case when ar then 'رحلة' else 'a trip' end
     when 'occasion' then case when ar then 'مناسبة' else 'an occasion' end
     else case when ar then 'عنصرًا' else 'an item' end end;
   t:=who||' '||case when coalesce(new.action,'added')='shared'
       then case when ar then 'شارك' else 'shared' end
       else case when ar then 'أضاف' else 'added' end end||' '||thing;
   b:=title||coalesce(' · '||new.detail,'');
 elsif new.kind='change' then
   verb:=case coalesce(new.action,'')
     when 'moved' then case when ar then 'غيّر موعد' else 'moved' end
     when 'completed' then case when ar then 'أكمل' else 'completed' end
     when 'cancelled' then case when ar then 'ألغى' else 'cancelled' end
     when 'reopened' then case when ar then 'أعاد فتح' else 'reopened' end
     when 'decided' then case when ar then 'حسم' else 'decided on' end
     when 'purchased' then case when ar then 'اشترى' else 'bought' end
     when 'booked' then case when ar then 'حجز' else 'booked' end
     when 'on_hold' then case when ar then 'أوقف مؤقتًا' else 'put on hold' end
     when 'removed' then case when ar then 'حذف' else 'removed' end
     when 'restored' then case when ar then 'استعاد' else 'restored' end
     when 'assigned' then case when ar then 'كلّفك بـ' else 'assigned you' end
     when 'celebrated' then case when ar then 'احتفل بـ' else 'celebrated' end
     when 'ready' then case when ar then 'جهّز' else 'is ready for' end
     when 'planned' then case when ar then 'خطط لـ' else 'planned' end
     when 'enjoyed' then case when ar then 'استمتع بـ' else 'enjoyed' end
     when 'started' then case when ar then 'بدأ' else 'started' end
     else case when ar then 'حدّث' else 'updated' end end;
   t:=who||' '||verb||' '||title;
   b:=coalesce(new.detail,case new.action
     when 'removed' then case when ar then 'يمكنك استعادته من المحذوفات' else 'You can still see it under Removed and restore it' end
     else case new.object_kind
       when 'task' then case when ar then 'مهمة' else 'To-do' end
       when 'activity' then case when ar then 'نشاط' else 'Activity' end
       when 'calendar' then case when ar then 'موعد' else 'Event' end
       when 'trip' then case when ar then 'رحلة' else 'Trip' end
       when 'occasion' then case when ar then 'مناسبة' else 'Occasion' end
       when 'experience' then case when ar then 'تجربة' else 'Shared experience' end
       when 'reminder' then case when ar then 'تذكير' else 'Reminder' end
       else case when ar then 'ذكرى' else 'Memory' end end end);
 else
   t:=who; b:=title;
 end if;

 if new.batch_count>1 then
   b:=b||case when ar then ' (+'||(new.batch_count-1)||' أخرى)'
     else ' (+'||(new.batch_count-1)||' more)' end;
 end if;
 new.push_title:=left(coalesce(nullif(btrim(t),''),'OneSpace'),120);
 new.push_body:=left(coalesce(nullif(btrim(b),''),' '),240);
 return new;
end $$;

drop trigger if exists compose_notification_text on public.space_notifications;
create trigger compose_notification_text
 before insert or update on public.space_notifications
 for each row execute function private.compose_notification_text();

-- 4. Queue: respect the push schedule and the recipient's sleep ---------------
create or replace function private.queue_notification_push()
returns trigger language plpgsql security definer set search_path to '' as $$
declare v_due timestamptz; v_quiet timestamptz;
begin
 if tg_op='UPDATE' and not(
    new.created_at is distinct from old.created_at
   or (new.read_at is null and old.read_at is not null)) then
  return new;
 end if;
 if new.read_at is not null then return new; end if;
 v_due:=greatest(coalesce(new.push_due_at,new.created_at),now()-interval '1 minute');
 -- D5: alerts triggered by the partner wait until wake-up. Reminders already
 -- apply their own rule (own reminders on time, Urgent overrides).
 if new.actor_id<>new.recipient_id and new.kind<>'reminder' then
   v_quiet:=private.reminder_quiet_until(new.recipient_id,v_due);
 end if;
 insert into private.push_outbox(notification_id,device_record_id,event_at,
   next_attempt_at,quiet_deferred)
 select new.id,d.id,coalesce(v_quiet,v_due),coalesce(v_quiet,v_due),v_quiet is not null
 from public.push_devices d
 where d.user_id=new.recipient_id and d.enabled
 and exists(select 1 from public.space_members m
   where m.space_id=new.space_id and m.user_id=new.recipient_id)
 on conflict(notification_id,device_record_id,event_at) do nothing;
 return new;
end $$;

-- 5. Claim: skip read items, fold wake-up summaries, return push text ---------
drop function if exists public.claim_push_outbox(integer);
create function public.claim_push_outbox(p_limit integer default 25)
returns table(delivery_id uuid, registration_token text, notification_id uuid,
  title text, body text, tag text, summary boolean)
language plpgsql security definer set search_path to '' as $$
begin
 if auth.role() is distinct from 'service_role'
 then raise exception 'Backend service authorization required';end if;

 -- Already seen in the app: no push.
 update private.push_outbox o set state='dead',lease_until=null,
   last_error='Read in the app before delivery'
 from public.space_notifications n
 where n.id=o.notification_id and o.state='pending' and n.read_at is not null;

 -- Several alerts held overnight for one phone become one summary.
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
     and exists(select 1 from public.space_members m
       where m.space_id=n.space_id and m.user_id=n.recipient_id)
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
end $$;
revoke all on function public.claim_push_outbox(integer) from public, anon, authenticated;
grant execute on function public.claim_push_outbox(integer) to service_role;

-- 6. Chat messages, trip messages, experience comments -------------------------
create or replace function private.notify_activity_comment()
returns trigger language plpgsql security definer set search_path to '' as $$
declare a record; peer record; previous_author uuid; v_kind text; v_text text;
begin
 select space_id,title,visibility,archived_at into a
 from public.activities where id=new.activity_id;
 if not found or a.visibility<>'shared' or a.archived_at is not null then return new; end if;
 select m.user_id as id, p.display_name as name into peer
 from public.space_members m join public.profiles p on p.id=m.user_id
 where m.space_id=a.space_id and m.user_id<>new.author_id limit 1;
 if not found then return new; end if;
 v_text:=nullif(btrim(coalesce(new.body,'')),'');
 if v_text is null and new.voice_path is not null then v_text:='🎤 Voice message'; end if;
 if length(btrim(coalesce(peer.name,'')))>0 and (
    position(lower('@'||peer.name) in lower(coalesce(new.body,'')))>0
    or position(lower('@'||split_part(peer.name,' ',1)) in lower(coalesce(new.body,'')))>0) then
   v_kind:='mention';
 elsif new.reply_to is not null then
   select author_id into previous_author from public.activity_comments
     where id=new.reply_to and activity_id=new.activity_id;
   if previous_author=peer.id then v_kind:='reply'; end if;
 end if;
 if v_kind is not null then
   -- Direct mentions and replies push straight away.
   perform private.post_notice(a.space_id,peer.id,new.author_id,v_kind,'activity',
     new.id,a.title,null,v_text,interval '0',new.activity_id);
 else
   -- D20: one row per Activity, at most one push per 10 minutes.
   perform private.post_notice(a.space_id,peer.id,new.author_id,'message','activity',
     new.activity_id,a.title,null,v_text,interval '10 minutes',new.activity_id);
 end if;
 return new;
end $$;

create or replace function private.notify_trip_message()
returns trigger language plpgsql security definer set search_path to '' as $$
declare trip record; peer uuid;
begin
 select space_id,title,visibility into trip from public.shared_trips where id=new.trip_id;
 if not found or trip.visibility<>'shared' then return new; end if;
 for peer in select m.user_id from public.space_members m
   where m.space_id=trip.space_id and m.user_id<>new.created_by loop
   perform private.post_notice(trip.space_id,peer,new.created_by,'trip_message','trip',
     new.trip_id,trip.title,null,new.body,interval '10 minutes',p_trip=>new.trip_id);
 end loop;
 return new;
end $$;

create or replace function private.experience_comment_notice()
returns trigger language plpgsql security definer set search_path to '' as $$
declare x record; peer uuid;
begin
 select space_id,title into x from public.shared_experiences where id=new.experience_id;
 if not found then return new; end if;
 for peer in select m.user_id from public.space_members m
   where m.space_id=x.space_id and m.user_id<>new.created_by loop
   perform private.post_notice(x.space_id,peer,new.created_by,'experience_comment','experience',
     new.experience_id,x.title,null,new.body,interval '10 minutes',p_experience=>new.experience_id);
 end loop;
 return new;
end $$;

-- 7. Meaningful changes to shared items ---------------------------------------
create or replace function private.notice_item_change()
returns trigger language plpgsql security definer set search_path to '' as $$
declare
 v_actor uuid:=auth.uid(); v_space uuid; v_title text; v_kind text; v_object_kind text;
 v_now_shared boolean; v_was_shared boolean; v_action text; v_new_item boolean:=false;
 v_at timestamptz; v_day date; v_day2 date; v_assignee uuid; v_peer uuid; v_detail text;
 v_link_activity uuid; v_link_calendar uuid; v_link_experience uuid; v_link_trip uuid;
 v_link_occasion uuid; v_link_memory uuid; v_ar boolean;
begin
 -- Only people act; the scheduler and service jobs never notify here.
 if v_actor is null then return new; end if;
 v_space:=new.space_id;
 if not exists(select 1 from public.space_members m
   where m.space_id=v_space and m.user_id=v_actor) then return new; end if;

 if tg_table_name='space_events' then
   if new.kind<>'event' then return new; end if;
   v_object_kind:='calendar'; v_title:=new.title; v_link_calendar:=new.id;
   v_now_shared:=new.visibility='shared';
   if tg_op='INSERT' then return new; end if; -- new events: notify_new_shared_event
   v_was_shared:=old.visibility='shared';
   if new.archived_at is null and old.archived_at is not null then v_action:='restored';
   elsif new.archived_at is not null and old.archived_at is null then v_action:='removed';
   elsif new.starts_at is distinct from old.starts_at
      or new.event_date is distinct from old.event_date then
     v_action:='moved'; v_at:=new.starts_at; v_day:=new.event_date;
   end if;
 elsif tg_table_name='tasks' then
   v_object_kind:='task'; v_title:=new.title;
   v_now_shared:=new.visibility='shared';
   if tg_op='INSERT' then
     if new.trip_template_key is not null then return new; end if; -- template batches stay quiet
     v_new_item:=true; v_assignee:=new.assigned_to;
     v_at:=new.deadline_at; v_day:=new.target_date;
   else
     v_was_shared:=old.visibility='shared';
     if new.status is distinct from old.status then
       v_action:=case new.status when 'completed' then 'completed'
         when 'cancelled' then 'cancelled' else 'reopened' end;
     elsif new.assigned_to is distinct from old.assigned_to and new.assigned_to is not null then
       v_action:='assigned'; v_assignee:=new.assigned_to;
     elsif (new.deadline_at is distinct from old.deadline_at
        or new.target_date is distinct from old.target_date)
        and (new.deadline_at is not null or new.target_date is not null) then
       v_action:='moved'; v_at:=new.deadline_at; v_day:=new.target_date;
     end if;
   end if;
 elsif tg_table_name='activities' then
   v_object_kind:='activity'; v_title:=new.title; v_link_activity:=new.id;
   v_now_shared:=new.visibility='shared';
   if tg_op='INSERT' then v_new_item:=true;
   else
     v_was_shared:=old.visibility='shared';
     if new.archived_at is null and old.archived_at is not null then v_action:='restored';
     elsif new.archived_at is not null and old.archived_at is null then v_action:='removed';
     elsif new.stage is distinct from old.stage then
       v_action:=case new.stage when 'decided' then 'decided' when 'purchased' then 'purchased'
         when 'registered' then 'booked' when 'completed' then 'completed'
         when 'cancelled' then 'cancelled' when 'on_hold' then 'on_hold'
         else case when old.stage in ('decided','purchased','registered','completed','cancelled','on_hold')
           then 'reopened' else null end end;
     elsif new.due_on is distinct from old.due_on and new.due_on is not null then
       v_action:='moved'; v_day:=new.due_on;
     end if;
   end if;
 elsif tg_table_name='occasion_plans' then
   v_object_kind:='occasion'; v_title:=new.title; v_link_occasion:=new.id;
   v_now_shared:=new.visibility='shared';
   if tg_op='INSERT' then return new; end if; -- notify_shared_occasion
   v_was_shared:=old.visibility='shared';
   if new.archived_at is null and old.archived_at is not null then v_action:='restored';
   elsif new.archived_at is not null and old.archived_at is null then v_action:='removed';
   elsif new.status is distinct from old.status and new.status in ('ready','celebrated','cancelled') then
     v_action:=new.status;
   elsif new.occasion_on is distinct from old.occasion_on then
     v_action:='moved'; v_day:=new.occasion_on;
   end if;
 elsif tg_table_name='shared_trips' then
   v_object_kind:='trip'; v_title:=new.title; v_link_trip:=new.id;
   v_now_shared:=new.visibility='shared';
   if tg_op='INSERT' then return new; end if; -- notify_trip_created
   v_was_shared:=old.visibility='shared';
   if new.archived_at is null and old.archived_at is not null then v_action:='restored';
   elsif new.archived_at is not null and old.archived_at is null then v_action:='removed';
   elsif new.status is distinct from old.status and new.status in ('booked','traveling','completed','cancelled') then
     v_action:=case new.status when 'traveling' then 'started' else new.status end;
   elsif new.start_on is distinct from old.start_on or new.end_on is distinct from old.end_on then
     v_action:='moved'; v_day:=new.start_on; v_day2:=new.end_on;
   end if;
 elsif tg_table_name='shared_experiences' then
   v_object_kind:='experience'; v_title:=new.title; v_link_experience:=new.id;
   v_now_shared:=true;
   if tg_op='INSERT' then return new; end if; -- experience_suggestion_notice
   v_was_shared:=true;
   if new.archived_at is null and old.archived_at is not null then v_action:='restored';
   elsif new.archived_at is not null and old.archived_at is null then v_action:='removed';
   elsif new.status is distinct from old.status and new.status in ('planned','enjoyed') then
     v_action:=new.status;
   elsif new.planned_on is distinct from old.planned_on and new.planned_on is not null then
     v_action:='moved'; v_day:=new.planned_on;
   end if;
 elsif tg_table_name='memories' then
   v_object_kind:=case when new.memory_type='scrapbook' then 'scrapbook' else 'memory' end;
   v_title:=new.title; v_link_memory:=new.id;
   v_now_shared:=new.visibility='shared';
   if tg_op='INSERT' then v_new_item:=true;
   else
     v_was_shared:=old.visibility='shared';
     if new.archived_at is null and old.archived_at is not null then v_action:='restored';
     elsif new.archived_at is not null and old.archived_at is null then v_action:='removed';
     end if;
   end if;
 elsif tg_table_name='reminders' then
   v_object_kind:='reminder'; v_title:=new.title;
   v_now_shared:=new.visibility='shared' and new.audience in ('partner','both');
   if tg_op='INSERT' then v_new_item:=true; v_at:=new.due_at;
   else
     v_was_shared:=old.visibility='shared' and old.audience in ('partner','both');
     if new.archived_at is null and old.archived_at is not null then v_action:='restored';
     elsif new.archived_at is not null and old.archived_at is null then v_action:='removed';
     end if;
   end if;
 else
   return new;
 end if;

 if not coalesce(v_now_shared,false) then return new; end if;
 -- Private -> shared counts as a new item for the partner.
 if tg_op='UPDATE' and not coalesce(v_was_shared,false) then
   v_new_item:=true; v_action:='shared';
 end if;
 if tg_op='INSERT' or v_new_item then
   if tg_op='UPDATE' and (to_jsonb(new)->>'archived_at') is not null then return new; end if;
 elsif v_action is null then
   return new; -- wording, notes, tags and other minor edits stay silent (spec 5.1)
 end if;

 for v_peer in select m.user_id from public.space_members m
   where m.space_id=v_space and m.user_id<>v_actor loop
   select coalesce(p.locale,'en')='ar' into v_ar from public.profiles p where p.id=v_peer;
   v_detail:=null;
   if v_at is not null or v_day is not null then
     v_detail:=private.notice_when(v_peer,v_at,case when v_at is null then v_day end);
     if v_day2 is not null and v_day2 is distinct from v_day then
       v_detail:=v_detail||' – '||to_char(v_day2,'Dy DD Mon');
     end if;
     if not v_new_item then
       v_detail:=case when coalesce(v_ar,false) then 'الموعد الجديد: ' else 'Now ' end||v_detail;
     end if;
   end if;
   if v_new_item and v_object_kind='task' and v_assignee=v_peer then
     -- A new to-do assigned to the partner says so in one push.
     perform private.post_notice(v_space,v_peer,v_actor,'change',v_object_kind,new.id,
       v_title,'assigned',v_detail,interval '2 minutes');
   elsif v_new_item then
     perform private.post_notice(v_space,v_peer,v_actor,'created',v_object_kind,new.id,
       v_title,coalesce(v_action,'added'),v_detail,interval '0',
       v_link_activity,v_link_calendar,v_link_experience,v_link_trip,v_link_occasion,v_link_memory);
   else
     if v_action='assigned' and v_assignee is distinct from v_peer then continue; end if;
     perform private.post_notice(v_space,v_peer,v_actor,'change',v_object_kind,new.id,
       v_title,v_action,v_detail,interval '2 minutes',
       v_link_activity,v_link_calendar,v_link_experience,v_link_trip,v_link_occasion,v_link_memory);
   end if;
 end loop;
 return new;
end $$;

drop trigger if exists r48_change_notice on public.space_events;
create trigger r48_change_notice after update on public.space_events
 for each row execute function private.notice_item_change();
drop trigger if exists r48_change_notice on public.tasks;
create trigger r48_change_notice after insert or update on public.tasks
 for each row execute function private.notice_item_change();
drop trigger if exists r48_change_notice on public.activities;
create trigger r48_change_notice after insert or update on public.activities
 for each row execute function private.notice_item_change();
drop trigger if exists r48_change_notice on public.occasion_plans;
create trigger r48_change_notice after update on public.occasion_plans
 for each row execute function private.notice_item_change();
drop trigger if exists r48_change_notice on public.shared_trips;
create trigger r48_change_notice after update on public.shared_trips
 for each row execute function private.notice_item_change();
drop trigger if exists r48_change_notice on public.shared_experiences;
create trigger r48_change_notice after update on public.shared_experiences
 for each row execute function private.notice_item_change();
drop trigger if exists r48_change_notice on public.memories;
create trigger r48_change_notice after insert or update on public.memories
 for each row execute function private.notice_item_change();
drop trigger if exists r48_change_notice on public.reminders;
create trigger r48_change_notice after insert or update on public.reminders
 for each row execute function private.notice_item_change();

revoke all on function private.post_notice(uuid,uuid,uuid,text,text,uuid,text,text,text,interval,uuid,uuid,uuid,uuid,uuid,uuid) from public;
revoke all on function private.notice_item_change() from public;
revoke all on function private.compose_notification_text() from public;

-- 8. Existing rows get push text once (no pushes are sent: created_at unchanged).
update public.space_notifications set batch_count=batch_count;
