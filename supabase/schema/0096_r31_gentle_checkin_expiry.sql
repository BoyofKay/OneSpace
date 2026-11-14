-- R31 — Gentle check-in request lifecycle.
-- Additive: legacy requests retain NULL expires_at and remain answerable.
-- Only NEW requests get the server-side seven-day default.
alter table public.partner_checkin_requests
 add column if not exists expires_at timestamptz;
alter table public.partner_checkin_requests
 alter column expires_at set default (now() + interval '7 days');
alter table public.partner_checkin_requests
 add constraint partner_checkin_expiry_after_send
 check (expires_at is null or expires_at > requested_at);
create index if not exists partner_checkin_pending_expiry
 on public.partner_checkin_requests (recipient_id,expires_at)
 where responded_at is null;

-- Update the existing trigger in place so even a forged API update cannot
-- answer an expired request. The original recipient-only RLS and column
-- grants remain untouched. There is no cron deleting or changing a row.
create or replace function private.timestamp_partner_checkin_reply()
returns trigger language plpgsql security definer set search_path='' as $$
begin
 if old.responded_at is not null then
  raise exception 'Already answered';
 end if;
 if old.expires_at is not null and now() >= old.expires_at then
  raise exception 'Check-in request expired. A new check-in can be sent.';
 end if;
 if new.response_mood is null then
  raise exception 'A mood rating is required';
 end if;
 new.responded_at:=now();
 return new;
end; $$;
