-- Applied 20261113091445: onespace_label_automated_gesture_alerts
-- Explicitly label an automated gesture in its in-app notification.
alter table public.space_notifications
 add column if not exists generated_automatically boolean not null default false;
create or replace function private.notify_partner_gesture()
returns trigger language plpgsql security definer set search_path='' as $$
begin
 insert into public.space_notifications
  (space_id,recipient_id,actor_id,kind,object_kind,object_id,
   headline,generated_automatically)
 values(new.space_id,new.recipient_id,new.sender_id,'gesture','gesture',
   new.id,left(new.message,180),new.automated)
 on conflict do nothing;
 return new;
end;$$;
revoke all on function private.notify_partner_gesture()
 from public,anon,authenticated;
