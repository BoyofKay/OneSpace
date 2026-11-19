-- QA 0191: PL/pgSQL dynamic EXECUTE does not update FOUND.
-- Check the fetched record itself; otherwise every valid link is rejected.
create or replace function private.qa_portable_target_scope(
 p_kind text,p_id uuid,p_space uuid,p_recipient uuid
) returns text language plpgsql stable security definer set search_path='' as $fn$
declare tab text; v record;
begin
 if auth.uid() is null or auth.uid()<>p_recipient then
 return 'blocked';end if;
 if not exists(select 1 from public.space_members sm
  where sm.space_id=p_space and sm.user_id=p_recipient) then
 return 'blocked';end if;
 if p_kind='experience' then
   if exists(select 1 from public.shared_experiences x
     where x.id=p_id and x.space_id=p_space) then return 'shared';end if;
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
 if v.visibility='shared' then return 'shared';end if;
 if v.visibility='private' and v.created_by=p_recipient
 then return 'private';end if;
 return 'blocked';
end $fn$;
revoke all on function private.qa_portable_target_scope(text,uuid,uuid,uuid) from public,anon,authenticated;
