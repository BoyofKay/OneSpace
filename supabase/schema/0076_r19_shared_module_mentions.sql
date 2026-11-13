-- R19: real shared @partner notifications in Calendar, To-dos, Occasions, Experiences.
-- Private records never notify. Existing note mention path remains unchanged.
alter table public.space_notifications drop constraint space_notifications_object_kind_check;
alter table public.space_notifications add constraint space_notifications_object_kind_check
 check(object_kind in ('activity','letter','calendar','gesture','note',
  'checkin','checkin_request','experience','trip','occasion','task'));
create function private.notify_shared_module_mention() returns trigger
language plpgsql security definer set search_path='' as $$
declare v_space uuid;v_kind text;v_title text;v_text text;v_visible boolean;
 v_partner record;v_actor uuid;
begin
 v_actor:=auth.uid();
 if v_actor is null then return new;end if;
 if TG_TABLE_NAME='space_events' then
  v_space:=new.space_id;v_kind:='calendar';v_title:=new.title;
  v_text:=coalesce(new.title,'')||' '||coalesce(new.details,'');
  v_visible:=new.visibility='shared' and new.archived_at is null;
  if TG_OP='UPDATE' and new.title is not distinct from old.title
   and new.details is not distinct from old.details then return new;end if;
 elsif TG_TABLE_NAME='tasks' then
  v_space:=new.space_id;v_kind:='task';v_title:=new.title;
  v_text:=coalesce(new.title,'');
  v_visible:=new.visibility='shared';
  if TG_OP='UPDATE' and new.title is not distinct from old.title then return new;end if;
 elsif TG_TABLE_NAME='occasion_plans' then
  v_space:=new.space_id;v_kind:='occasion';v_title:=new.title;
  v_text:=coalesce(new.title,'')||' '||coalesce(new.notes,'');
  v_visible:=new.visibility='shared' and new.archived_at is null;
  if TG_OP='UPDATE' and new.title is not distinct from old.title
   and new.notes is not distinct from old.notes then return new;end if;
 elsif TG_TABLE_NAME='shared_experiences' then
  v_space:=new.space_id;v_kind:='experience';v_title:=new.title;
  v_text:=coalesce(new.title,'')||' '||coalesce(new.description,'');
  v_visible:=new.archived_at is null;
  if TG_OP='UPDATE' and new.title is not distinct from old.title
   and new.description is not distinct from old.description then return new;end if;
 else return new;end if;
 if not v_visible or not exists(select 1 from public.space_members m
  where m.space_id=v_space and m.user_id=v_actor) then return new;end if;
 for v_partner in select m.user_id,p.display_name from public.space_members m
  join public.profiles p on p.id=m.user_id
  where m.space_id=v_space and m.user_id<>v_actor
 loop
  if length(btrim(coalesce(v_partner.display_name,'')))=0 then continue;end if;
  if position(lower('@'||v_partner.display_name) in lower(v_text))=0 then continue;end if;
  insert into public.space_notifications
    (space_id,recipient_id,actor_id,kind,object_kind,object_id,headline,
      calendar_event_id,experience_id,occasion_id)
  values(v_space,v_partner.user_id,v_actor,'mention',v_kind,new.id,
    left(v_title,180),
    case when v_kind='calendar' then new.id else null end,
    case when v_kind='experience' then new.id else null end,
    case when v_kind='occasion' then new.id else null end)
  on conflict (recipient_id,kind,object_id)
   do update set actor_id=excluded.actor_id,created_at=now(),read_at=null,
    headline=excluded.headline;
 end loop;
 return new;
end; $$;
revoke all on function private.notify_shared_module_mention() from public,anon,authenticated;
create trigger calendar_partner_mention after insert or update of title,details
 on public.space_events for each row execute function private.notify_shared_module_mention();
create trigger todo_partner_mention after insert or update of title
 on public.tasks for each row execute function private.notify_shared_module_mention();
create trigger occasion_partner_mention after insert or update of title,notes
 on public.occasion_plans for each row execute function private.notify_shared_module_mention();
create trigger experience_partner_mention after insert or update of title,description
 on public.shared_experiences for each row execute function private.notify_shared_module_mention();
