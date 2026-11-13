-- Deployed Supabase migration 20261113084025 (onespace_connect_affection_gestures_and_notifications).
-- Exact SQL captured from Supabase migration history.
-- OneSpace R3 Connect: explicit affectionate gestures, no automation or impersonation.
create table public.partner_gestures (
 id uuid primary key default gen_random_uuid(),
 space_id uuid not null references public.spaces(id) on delete cascade,
 sender_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
 recipient_id uuid not null references auth.users(id) on delete cascade,
 kind text not null check(kind in (
  'hug','thinking','smile','morning','goodnight','proud','support'
 )),
 message text not null check(char_length(btrim(message)) between 1 and 240),
 created_at timestamptz not null default now(),
 check(sender_id <> recipient_id)
);
create index partner_gestures_space_recent on public.partner_gestures(space_id,created_at desc);
alter table public.partner_gestures enable row level security;
create policy "Partners may see gestures addressed within their space"
on public.partner_gestures for select to authenticated
using (private.is_space_member(space_id)
  and (sender_id=(select auth.uid()) or recipient_id=(select auth.uid())));
create policy "Only the actual sender can send to the other space member"
on public.partner_gestures for insert to authenticated
with check (
 sender_id=(select auth.uid()) and
 private.is_space_member(space_id) and
 recipient_id<>(select auth.uid()) and
 exists(select 1 from public.space_members m
   where m.space_id=partner_gestures.space_id
   and m.user_id=partner_gestures.recipient_id)
);
revoke all on public.partner_gestures from public,anon,authenticated;
grant select on public.partner_gestures to authenticated;
grant insert(space_id,recipient_id,kind,message) on public.partner_gestures to authenticated;
alter publication supabase_realtime add table public.partner_gestures;
alter table public.space_notifications
 drop constraint space_notifications_kind_check;
alter table public.space_notifications
 add constraint space_notifications_kind_check
 check(kind in ('mention','reply','letter','event','gesture'));
alter table public.space_notifications
 drop constraint space_notifications_object_kind_check;
alter table public.space_notifications
 add constraint space_notifications_object_kind_check
 check(object_kind in ('activity','letter','calendar','gesture'));
create function private.notify_partner_gesture() returns trigger
 language plpgsql security definer set search_path='' as $$
begin
 insert into public.space_notifications
  (space_id,recipient_id,actor_id,kind,object_kind,object_id,headline)
 values(new.space_id,new.recipient_id,new.sender_id,'gesture','gesture',
   new.id,left(new.message,180))
 on conflict do nothing;
 return new;
end; $$;
create trigger partner_gestures_notify
 after insert on public.partner_gestures
 for each row execute function private.notify_partner_gesture();
revoke all on function private.notify_partner_gesture()
 from public,anon,authenticated;
