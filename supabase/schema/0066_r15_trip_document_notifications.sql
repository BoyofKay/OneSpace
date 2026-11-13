-- R15: notify partners about shared travel documents and stream metadata.
-- No existing notification row or trip is changed.
alter table public.space_notifications drop constraint space_notifications_kind_check;
alter table public.space_notifications add constraint space_notifications_kind_check
 check (kind in ('mention','reply','letter','event','gesture','reminder',
 'checkin_request','checkin_response','checkin_shared',
 'experience_suggestion','experience_comment','trip_suggestion','trip_message',
 'trip_document'));

create function private.notify_trip_document()
returns trigger language plpgsql security definer set search_path='' as $$
declare info record;
begin
 select space_id,title,visibility into info
 from public.shared_trips where id=new.trip_id;
 if not found or info.visibility<>'shared' then return new; end if;
 insert into public.space_notifications
   (space_id,recipient_id,actor_id,kind,object_kind,object_id,trip_id,headline)
 select info.space_id,m.user_id,new.created_by,'trip_document','trip',
    new.id,new.trip_id,left('Travel document shared: '||new.title,180)
 from public.space_members m
 where m.space_id=info.space_id and m.user_id<>new.created_by
 on conflict do nothing;
 return new;
end; $$;
create trigger trip_document_notification
 after insert on public.trip_attachments for each row
 execute function private.notify_trip_document();
revoke all on function private.notify_trip_document()
 from public,anon,authenticated;

alter publication supabase_realtime add table public.trip_attachments;
