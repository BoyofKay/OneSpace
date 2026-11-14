-- R41: complete @partner notifications in shared Reminders.
-- This is independent from reminder delivery alerts and recipient outcomes.
create or replace function private.notify_shared_reminder_mention()
returns trigger language plpgsql security definer
set search_path='' as $$
declare actor uuid;partner record;content text;
begin
 actor:=auth.uid();
 if actor is null or new.visibility<>'shared' or
   new.archived_at is not null then return new;end if;
 if tg_op='UPDATE' and
  new.title is not distinct from old.title and
  new.details is not distinct from old.details then return new;end if;
 if not exists(select 1 from public.space_members m
  where m.space_id=new.space_id and m.user_id=actor) then
  return new;end if;
 content:=coalesce(new.title,'')||' '||coalesce(new.details,'');
 for partner in
  select m.user_id,p.display_name
  from public.space_members m join public.profiles p on p.id=m.user_id
  where m.space_id=new.space_id and m.user_id<>actor
 loop
  if char_length(btrim(coalesce(partner.display_name,'')))=0 then continue;end if;
  if position(lower('@'||partner.display_name) in lower(content))=0
   then continue;end if;
  insert into public.space_notifications(
   space_id,recipient_id,actor_id,kind,object_kind,object_id,headline)
  values(new.space_id,partner.user_id,actor,'mention','reminder',
   new.id,left(new.title,180))
  on conflict (recipient_id,kind,object_id)
   do update set actor_id=excluded.actor_id,created_at=now(),
    read_at=null,headline=excluded.headline;
 end loop;
 return new;
end;
$$;
revoke all on function private.notify_shared_reminder_mention()
 from public,anon,authenticated;
create trigger r41_reminder_partner_mention
 after insert or update on public.reminders for each row
 execute function private.notify_shared_reminder_mention();
