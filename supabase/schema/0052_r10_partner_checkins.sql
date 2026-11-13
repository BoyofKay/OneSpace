-- Deployed 20261113120326 onespace_r10_partner_checkin_requests_responses_and_notifications
create table public.partner_checkin_requests(
 id uuid primary key default gen_random_uuid(),
 space_id uuid not null references public.spaces(id) on delete cascade,
 sender_id uuid not null references auth.users(id),
 recipient_id uuid not null references auth.users(id),
 note text not null default '' check(length(note)<=500),
 requested_at timestamptz not null default now(),
 responded_at timestamptz,
 response_mood smallint check(response_mood between 1 and 5),
 response_message text not null default '' check(length(response_message)<=2000),
 response_topic text not null default '' check(length(response_topic)<=1000),
 check(sender_id<>recipient_id),
 check((responded_at is null and response_mood is null)
    or (responded_at is not null and response_mood is not null))
);
create index checkin_requests_space_recent on public.partner_checkin_requests(space_id,requested_at desc);
create index checkin_requests_pending on public.partner_checkin_requests(recipient_id,requested_at desc) where responded_at is null;
alter table public.partner_checkin_requests enable row level security;
create policy "Only participants view checkin conversations"
 on public.partner_checkin_requests for select to authenticated
 using((sender_id=(select auth.uid()) or recipient_id=(select auth.uid()))
   and private.is_space_member(space_id));
create policy "Send checkin to member of your space"
 on public.partner_checkin_requests for insert to authenticated
 with check(sender_id=(select auth.uid()) and private.is_space_member(space_id)
  and exists(select 1 from public.space_members m
    where m.space_id=partner_checkin_requests.space_id and m.user_id=partner_checkin_requests.recipient_id)
  and responded_at is null and response_mood is null);
create policy "Only recipient replies once"
 on public.partner_checkin_requests for update to authenticated
 using(recipient_id=(select auth.uid()) and private.is_space_member(space_id)
   and responded_at is null)
 with check(recipient_id=(select auth.uid()) and private.is_space_member(space_id));
revoke all on public.partner_checkin_requests from public,anon,authenticated;
grant select on public.partner_checkin_requests to authenticated;
grant insert(space_id,sender_id,recipient_id,note) on public.partner_checkin_requests to authenticated;
grant update(response_mood,response_message,response_topic) on public.partner_checkin_requests to authenticated;
create function private.timestamp_partner_checkin_reply()
returns trigger language plpgsql security definer set search_path='' as $$
begin
 if old.responded_at is not null then raise exception 'Already answered'; end if;
 if new.response_mood is null then raise exception 'A mood rating is required'; end if;
 new.responded_at:=now();
 return new;
end;$$;
create trigger checkin_reply_timestamp
before update on public.partner_checkin_requests for each row
execute function private.timestamp_partner_checkin_reply();

alter table public.space_notifications drop constraint space_notifications_kind_check;
alter table public.space_notifications add constraint space_notifications_kind_check
 check(kind in ('mention','reply','letter','event','gesture','reminder',
 'checkin_request','checkin_response','checkin_shared'));
alter table public.space_notifications drop constraint space_notifications_object_kind_check;
alter table public.space_notifications add constraint space_notifications_object_kind_check
 check(object_kind in ('activity','letter','calendar','gesture','note','checkin','checkin_request'));

create function private.notify_partner_checkin_requests()
returns trigger language plpgsql security definer set search_path='' as $$
begin
 if tg_op='INSERT' then
   insert into public.space_notifications
    (space_id,recipient_id,actor_id,kind,object_kind,object_id,headline)
   values(new.space_id,new.recipient_id,new.sender_id,'checkin_request',
      'checkin_request',new.id,'Your love is checking in with you')
   on conflict do nothing;
 elsif tg_op='UPDATE' and old.responded_at is null and new.responded_at is not null then
   insert into public.space_notifications
    (space_id,recipient_id,actor_id,kind,object_kind,object_id,headline)
   values(new.space_id,new.sender_id,new.recipient_id,'checkin_response',
      'checkin_request',new.id,'Your partner replied to your check-in')
   on conflict do nothing;
 end if;
 return new;
end;$$;
create trigger notify_partner_checkin_request
 after insert or update on public.partner_checkin_requests
 for each row execute function private.notify_partner_checkin_requests();

create function private.notify_shared_daily_checkin()
returns trigger language plpgsql security definer set search_path='' as $$
declare peer uuid;
begin
 if new.visibility<>'shared' then return new; end if;
 for peer in select user_id from public.space_members
   where space_id=new.space_id and user_id<>new.created_by loop
   insert into public.space_notifications
    (space_id,recipient_id,actor_id,kind,object_kind,object_id,headline)
   values(new.space_id,peer,new.created_by,'checkin_shared',
      'checkin',new.id,'Your partner shared how they feel today')
   on conflict do nothing;
 end loop;
 return new;
end;$$;
create trigger notify_shared_daily_checkin
 after insert on public.daily_checkins
 for each row execute function private.notify_shared_daily_checkin();

alter publication supabase_realtime add table public.partner_checkin_requests;
