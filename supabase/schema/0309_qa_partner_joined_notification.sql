-- QA 0309: tell the space owner when their partner joins.
--
-- Before: joining a space created no notification, so the inviter only found
-- out by reopening the app. Adds a 'joined' notification (push text in English
-- and Arabic) sent to the existing member when a second person joins.
-- compose_notification_text is the 0109 version plus the 'joined' branch.
-- QA only; never apply to Production.

alter table public.space_notifications drop constraint if exists space_notifications_kind_check;
alter table public.space_notifications add constraint space_notifications_kind_check check (kind = any (array[
    'mention','reply','letter','event','gesture','reminder','checkin_request',
    'checkin_response','checkin_shared','experience_suggestion','experience_comment',
    'trip_suggestion','trip_message','trip_document','occasion_shared','scrapbook_invite',
    'message','created','change','joined'])) not valid;

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
 elsif new.kind='joined' then
   t:=who||case when ar then ' انضم إلى مساحتكما' else ' joined your space' end;
   b:=case when ar then 'يمكنكما الآن مشاركة الأشياء معًا' else 'You can now share things together' end;
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

create or replace function private.notify_partner_joined()
returns trigger language plpgsql security definer set search_path to '' as $$
declare other uuid;
begin
 for other in select m.user_id from public.space_members m
   where m.space_id=new.space_id and m.user_id<>new.user_id loop
   perform private.post_notice(new.space_id,other,new.user_id,'joined','space',
     new.space_id,'Joined',null,null,interval '0');
 end loop;
 return new;
end $$;
revoke all on function private.notify_partner_joined() from public,anon,authenticated;
drop trigger if exists notify_partner_joined on public.space_members;
create trigger notify_partner_joined after insert on public.space_members
 for each row execute function private.notify_partner_joined();
