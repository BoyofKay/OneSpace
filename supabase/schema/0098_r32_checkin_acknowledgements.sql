-- R32 — Optional response acknowledgment for Daily Connection.
-- Additive, no changes to requests, responses, existing reminders or push.
-- Only the request sender can acknowledge an actual reply.
create table public.partner_checkin_acknowledgements (
 request_id uuid primary key references public.partner_checkin_requests(id)
  on delete cascade,
 user_id uuid not null default auth.uid() references auth.users(id),
 kind text not null check(kind in ('heart','thank_you','hug')),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create index checkin_ack_user_recent
 on public.partner_checkin_acknowledgements(user_id,updated_at desc);
alter table public.partner_checkin_acknowledgements enable row level security;
create policy "Participants read answered checkin acknowledgment"
 on public.partner_checkin_acknowledgements
 for select to authenticated using (
  exists (select 1 from public.partner_checkin_requests r
   where r.id=request_id and r.responded_at is not null
    and private.is_space_member(r.space_id)
    and ((select auth.uid())=r.sender_id
      or (select auth.uid())=r.recipient_id))
 );
create policy "Only original sender acknowledges an answered checkin"
 on public.partner_checkin_acknowledgements
 for insert to authenticated with check (
  user_id=(select auth.uid()) and
  exists (select 1 from public.partner_checkin_requests r
   where r.id=request_id and r.responded_at is not null
    and r.sender_id=(select auth.uid())
    and private.is_space_member(r.space_id))
 );
create policy "Only sender changes own checkin acknowledgment"
 on public.partner_checkin_acknowledgements
 for update to authenticated using (
  user_id=(select auth.uid()) and
  exists (select 1 from public.partner_checkin_requests r
   where r.id=request_id and r.responded_at is not null
    and r.sender_id=(select auth.uid())
    and private.is_space_member(r.space_id))
 )
 with check (
  user_id=(select auth.uid()) and
  exists (select 1 from public.partner_checkin_requests r
   where r.id=request_id and r.responded_at is not null
    and r.sender_id=(select auth.uid())
    and private.is_space_member(r.space_id))
 );
revoke all on public.partner_checkin_acknowledgements from public,anon,authenticated;
grant select on public.partner_checkin_acknowledgements to authenticated;
grant insert (request_id,kind) on public.partner_checkin_acknowledgements to authenticated;
grant update (kind) on public.partner_checkin_acknowledgements to authenticated;

create function private.touch_checkin_ack()
 returns trigger language plpgsql set search_path='' as $$
begin new.updated_at:=now(); return new; end $$;
create trigger update_checkin_ack_timestamp
 before update on public.partner_checkin_acknowledgements
 for each row execute function private.touch_checkin_ack();
revoke all on function private.touch_checkin_ack()
 from public,anon,authenticated;
alter publication supabase_realtime add table public.partner_checkin_acknowledgements;
