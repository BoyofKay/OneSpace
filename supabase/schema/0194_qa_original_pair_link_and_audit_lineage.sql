-- QA 0194: shared references require original creator still in the exact space;
-- never let a former partner's records ride into another relationship.
CREATE OR REPLACE FUNCTION private.qa_action_history_record_scope(p_kind text, p_id uuid, p_space uuid, p_recipient uuid)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare tab text; v record; membership int;
begin
 if auth.uid() is null or auth.uid()<>p_recipient then return 'blocked';end if;
 if not exists(select 1 from public.space_members m
  where m.space_id=p_space and m.user_id=p_recipient) then return 'blocked';end if;
 if p_kind in ('note','task','memory','event','reminder','occasion','trip','activity','experience') then
 return private.qa_portable_target_scope(p_kind,p_id,p_space,p_recipient);
 end if;
 if p_kind='experience_comment' then
   select c.created_by,c.archived_at,x.space_id into v
     from public.shared_experience_comments c
     join public.shared_experiences x on x.id=c.experience_id
     where c.id=p_id and x.space_id=p_space
       and exists(select 1 from public.space_members sm
          where sm.space_id=x.space_id and sm.user_id=c.created_by)
       and exists(select 1 from public.space_members sm
          where sm.space_id=x.space_id and sm.user_id=x.created_by);
   if v is null then return 'blocked';end if;
   if v.archived_at is not null then
     return case when v.created_by=p_recipient then 'private' else 'blocked' end;
   end if;
   return 'shared';
 end if;
 if p_kind='checkin_request' then
  if exists(select 1 from public.partner_checkin_requests r
      where r.id=p_id and r.space_id=p_space and p_recipient in (r.sender_id,r.recipient_id)
        and exists(select 1 from public.space_members m where m.space_id=p_space and m.user_id=r.sender_id)
        and exists(select 1 from public.space_members m where m.space_id=p_space and m.user_id=r.recipient_id))
  then return 'shared';end if;
  return 'blocked';
 end if;
 tab:=case p_kind
 when 'goal' then 'goals'
 when 'contact' then 'saved_contacts'
 when 'sort_item' then 'items_to_sort'
 when 'checkin' then 'daily_checkins'
 else null end;
 if tab is null then return 'blocked';end if;
 execute format('select t.created_by,t.visibility from public.%I t
 where t.id=$1 and t.space_id=$2',tab) into v using p_id,p_space;
 if v is null then return 'blocked';end if;
 if v.visibility='shared' then
   if exists(select 1 from public.space_members sm
      where sm.space_id=p_space and sm.user_id=v.created_by)
   then return 'shared';end if;
   return 'blocked';
 end if;
 if v.visibility='private' and v.created_by=p_recipient then return 'private';end if;
 return 'blocked';
end $function$
;
revoke all on function private.qa_action_history_record_scope(text,uuid,uuid,uuid) from public,anon,authenticated;
CREATE OR REPLACE FUNCTION private.qa_portable_target_scope(p_kind text, p_id uuid, p_space uuid, p_recipient uuid)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare tab text; v record;
begin
 if auth.uid() is null or auth.uid()<>p_recipient then
 return 'blocked';end if;
 if not exists(select 1 from public.space_members sm
  where sm.space_id=p_space and sm.user_id=p_recipient) then
 return 'blocked';end if;
 if p_kind='experience' then
   if exists(select 1 from public.shared_experiences x
     where x.id=p_id and x.space_id=p_space
       and exists(select 1 from public.space_members sm
         where sm.space_id=x.space_id and sm.user_id=x.created_by))
       then return 'shared';end if;
   return 'blocked';
 end if;
 tab:=case p_kind
 when 'activity' then 'activities' when 'trip' then 'shared_trips'
 when 'occasion' then 'occasion_plans' when 'event' then 'space_events'
 when 'reminder' then 'reminders' when 'task' then 'tasks'
 when 'note' then 'notes' when 'memory' then 'memories'
 else null end;
 if tab is null then return 'blocked';end if;
 execute format('select t.visibility,t.created_by from public.%I t
 where t.id=$1 and t.space_id=$2',tab)
 into v using p_id,p_space;
 if v is null then return 'blocked';end if;
 if v.visibility='shared' then
   if exists(select 1 from public.space_members sm
      where sm.space_id=p_space and sm.user_id=v.created_by)
   then return 'shared';end if;
   return 'blocked';
 end if;
 if v.visibility='private' and v.created_by=p_recipient
 then return 'private';end if;
 return 'blocked';
end $function$
;
revoke all on function private.qa_portable_target_scope(text,uuid,uuid,uuid) from public,anon,authenticated;
