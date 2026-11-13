-- R14: trips and journeys, fully additive. No account, membership, or data deletion.
create table public.shared_trips (
 id uuid primary key default gen_random_uuid(),
 space_id uuid not null references public.spaces(id) on delete cascade,
 created_by uuid not null default auth.uid() references auth.users(id),
 title text not null check (char_length(btrim(title)) between 1 and 160),
 origin text not null default '' check (char_length(origin)<=160),
 destination text not null default '' check (char_length(destination)<=160),
 start_on date,
 end_on date,
 notes text not null default '' check(char_length(notes)<=5000),
 status text not null default 'planning'
  check(status in ('planning','booked','traveling','completed','cancelled')),
 visibility text not null default 'shared' check(visibility in ('shared','private')),
 archived_at timestamptz,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 check(end_on is null or start_on is null or end_on>=start_on)
);
create index shared_trips_space_dates on public.shared_trips(space_id,start_on,updated_at desc);
alter table public.shared_trips enable row level security;
create policy "Read own or shared trips" on public.shared_trips
 for select to authenticated
 using(private.is_space_member(space_id) and
  (visibility='shared' or created_by=(select auth.uid())));
create policy "Create own trips" on public.shared_trips
 for insert to authenticated
 with check(created_by=(select auth.uid()) and private.is_space_member(space_id));
create policy "Collaborate on shared trips or own private trips" on public.shared_trips
 for update to authenticated
 using(private.is_space_member(space_id) and
  (visibility='shared' or created_by=(select auth.uid())))
 with check(private.is_space_member(space_id) and
  (visibility='shared' or created_by=(select auth.uid())));
revoke all on public.shared_trips from public,anon,authenticated;
grant select on public.shared_trips to authenticated;
grant insert(space_id,title,origin,destination,start_on,end_on,notes,status,visibility)
 on public.shared_trips to authenticated;
-- Privacy/owner/space are immutable after creation; no public delete grants.
grant update(title,origin,destination,start_on,end_on,notes,status,archived_at)
 on public.shared_trips to authenticated;

create table public.trip_items (
 id uuid primary key default gen_random_uuid(),
 trip_id uuid not null references public.shared_trips(id) on delete cascade,
 created_by uuid not null default auth.uid() references auth.users(id),
 kind text not null check (kind in
 ('flight','stay','transport','activity','booking','note')),
 title text not null check(char_length(btrim(title)) between 1 and 160),
 location text not null default '' check(char_length(location)<=240),
 destination text not null default '' check(char_length(destination)<=240),
 local_date date,
 local_time time without time zone,
 end_date date,
 end_time time without time zone,
 provider text not null default '' check(char_length(provider)<=160),
 booking_reference text not null default '' check(char_length(booking_reference)<=120),
 source_url text not null default '' check(char_length(source_url)<=1800),
 details text not null default '' check(char_length(details)<=5000),
 estimated_cost numeric(12,2) check(estimated_cost>=0),
 currency text not null default 'USD'
  check(currency~'^[A-Z]{3}$'),
 done boolean not null default false,
 archived_at timestamptz,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 check(end_date is null or local_date is null or end_date>=local_date)
);
create index trip_items_trip_day on public.trip_items(trip_id,local_date,local_time);
alter table public.trip_items enable row level security;
create policy "Read visible trip items" on public.trip_items
 for select to authenticated using(exists(
  select 1 from public.shared_trips t where t.id=trip_id));
create policy "Contribute itinerary to visible editable trip" on public.trip_items
 for insert to authenticated with check(
  created_by=(select auth.uid()) and exists(
   select 1 from public.shared_trips t where t.id=trip_id and
   (t.visibility='shared' or t.created_by=(select auth.uid()))));
create policy "Edit shared itinerary or own private itinerary" on public.trip_items
 for update to authenticated
 using(exists(select 1 from public.shared_trips t where t.id=trip_id and
   (t.visibility='shared' or t.created_by=(select auth.uid()))))
 with check(exists(select 1 from public.shared_trips t where t.id=trip_id and
   (t.visibility='shared' or t.created_by=(select auth.uid()))));
revoke all on public.trip_items from public,anon,authenticated;
grant select on public.trip_items to authenticated;
grant insert(trip_id,kind,title,location,destination,local_date,local_time,
 end_date,end_time,provider,booking_reference,source_url,details,
 estimated_cost,currency,done) on public.trip_items to authenticated;
grant update(kind,title,location,destination,local_date,local_time,
 end_date,end_time,provider,booking_reference,source_url,details,
 estimated_cost,currency,done,archived_at) on public.trip_items to authenticated;

create table public.trip_messages (
 id uuid primary key default gen_random_uuid(),
 trip_id uuid not null references public.shared_trips(id) on delete cascade,
 created_by uuid not null default auth.uid() references auth.users(id),
 body text not null check(char_length(btrim(body)) between 1 and 3000),
 created_at timestamptz not null default now(),
 archived_at timestamptz
);
create index trip_messages_trip_recent on public.trip_messages(trip_id,created_at);
alter table public.trip_messages enable row level security;
create policy "Read messages for visible trips" on public.trip_messages
 for select to authenticated using(exists(
  select 1 from public.shared_trips t where t.id=trip_id));
create policy "Write own messages to visible trips" on public.trip_messages
 for insert to authenticated with check(created_by=(select auth.uid()) and exists(
  select 1 from public.shared_trips t where t.id=trip_id
  and (t.visibility='shared' or t.created_by=(select auth.uid()))));
create policy "Retract only own trip message" on public.trip_messages
 for update to authenticated
 using(created_by=(select auth.uid()) and exists(
   select 1 from public.shared_trips t where t.id=trip_id))
 with check(created_by=(select auth.uid()) and exists(
   select 1 from public.shared_trips t where t.id=trip_id));
revoke all on public.trip_messages from public,anon,authenticated;
grant select on public.trip_messages to authenticated;
grant insert(trip_id,body) on public.trip_messages to authenticated;
grant update(archived_at) on public.trip_messages to authenticated;

create table public.trip_revisions (
 id bigint generated always as identity primary key,
 trip_id uuid not null references public.shared_trips(id) on delete cascade,
 record_kind text not null check(record_kind in ('trip','item','message')),
 record_id uuid not null,
 changed_by uuid references auth.users(id),
 changed_at timestamptz not null default now(),
 before_snapshot jsonb not null,
 after_snapshot jsonb not null
);
create index trip_revisions_by_trip on public.trip_revisions(trip_id,changed_at desc);
alter table public.trip_revisions enable row level security;
create policy "Audit visible trips" on public.trip_revisions
 for select to authenticated using(exists(
  select 1 from public.shared_trips t where t.id=trip_id));
revoke all on public.trip_revisions from public,anon,authenticated;
grant select on public.trip_revisions to authenticated;

create function private.audit_trip_change()
returns trigger language plpgsql security definer set search_path='' as $$
declare v_trip uuid; v_kind text;
begin
 if TG_TABLE_NAME='shared_trips' then
   v_trip:=new.id;v_kind:='trip';
 elsif TG_TABLE_NAME='trip_items' then
   v_trip:=new.trip_id;v_kind:='item';
 else
   v_trip:=new.trip_id;v_kind:='message';
 end if;
 if TG_TABLE_NAME<>'trip_messages' then new.updated_at:=now();end if;
 if to_jsonb(old) is distinct from to_jsonb(new) then
   insert into public.trip_revisions
    (trip_id,record_kind,record_id,changed_by,before_snapshot,after_snapshot)
   values(v_trip,v_kind,new.id,auth.uid(),to_jsonb(old),to_jsonb(new));
 end if;
 return new;
end; $$;
create trigger trip_audit before update on public.shared_trips
 for each row execute function private.audit_trip_change();
create trigger trip_item_audit before update on public.trip_items
 for each row execute function private.audit_trip_change();
create trigger trip_message_audit before update on public.trip_messages
 for each row execute function private.audit_trip_change();
revoke all on function private.audit_trip_change() from public,anon,authenticated;

alter table public.space_notifications
 add column trip_id uuid references public.shared_trips(id) on delete set null;
alter table public.space_notifications drop constraint space_notifications_kind_check;
alter table public.space_notifications add constraint space_notifications_kind_check
 check(kind in ('mention','reply','letter','event','gesture','reminder',
 'checkin_request','checkin_response','checkin_shared',
 'experience_suggestion','experience_comment','trip_suggestion','trip_message'));
alter table public.space_notifications drop constraint space_notifications_object_kind_check;
alter table public.space_notifications add constraint space_notifications_object_kind_check
 check(object_kind in ('activity','letter','calendar','gesture','note',
 'checkin','checkin_request','experience','trip'));

create function private.notify_trip_created()
returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.visibility<>'shared' then return new; end if;
 insert into public.space_notifications
   (space_id,recipient_id,actor_id,kind,object_kind,object_id,trip_id,headline)
 select new.space_id,m.user_id,new.created_by,'trip_suggestion','trip',
   new.id,new.id,left('Our next adventure: '||new.title,180)
 from public.space_members m
 where m.space_id=new.space_id and m.user_id<>new.created_by
 on conflict do nothing;
 return new;
end; $$;
create trigger trip_created_notice after insert on public.shared_trips
 for each row execute function private.notify_trip_created();

create function private.notify_trip_message()
returns trigger language plpgsql security definer set search_path='' as $$
declare trip record;
begin
 select space_id,title,visibility into trip from public.shared_trips
  where id=new.trip_id;
 if not found or trip.visibility<>'shared' then return new; end if;
 insert into public.space_notifications
   (space_id,recipient_id,actor_id,kind,object_kind,object_id,trip_id,headline)
 select trip.space_id,m.user_id,new.created_by,'trip_message','trip',
   new.id,new.trip_id,left('New message on trip: '||trip.title,180)
 from public.space_members m
 where m.space_id=trip.space_id and m.user_id<>new.created_by
 on conflict do nothing;
 return new;
end; $$;
create trigger trip_message_notice after insert on public.trip_messages
 for each row execute function private.notify_trip_message();
revoke all on function private.notify_trip_created() from public,anon,authenticated;
revoke all on function private.notify_trip_message() from public,anon,authenticated;

alter publication supabase_realtime add table public.shared_trips;
alter publication supabase_realtime add table public.trip_items;
alter publication supabase_realtime add table public.trip_messages;
