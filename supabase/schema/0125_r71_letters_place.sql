-- R71 (forms review, rest of the modules). Non-destructive.
-- 1. Letters can wait for a day ("Open on"): the partner sees a sealed
--    envelope with the date, and the letter itself on that day.
-- 2. A story can say where it happened.

alter table public.couple_letters
  add column if not exists open_on date,
  add column if not exists delivered_at timestamptz;
grant insert (open_on) on public.couple_letters to authenticated;
grant update (open_on) on public.couple_letters to authenticated;

drop policy if exists "Letters visible to authorized partners" on public.couple_letters;
create policy "Letters visible to authorized partners" on public.couple_letters for select to authenticated
  using (private.is_space_member(space_id) and (
    author_id = (select auth.uid())
    or (status = 'sent' and (open_on is null or open_on <= current_date))));

-- A letter can't be scheduled in the past, and only up to ten years ahead.
create or replace function private.check_letter_open_on()
returns trigger language plpgsql security definer set search_path to '' as $$
begin
  if new.open_on is not null and (tg_op='INSERT' or new.open_on is distinct from old.open_on)
     and (new.open_on < current_date or new.open_on > current_date + 3660) then
    raise exception 'Choose an opening day from today on';
  end if;
  if new.open_on is not null and new.open_on <= current_date then new.open_on := null; end if;
  return new;
end $$;
drop trigger if exists r71_letter_open_on on public.couple_letters;
create trigger r71_letter_open_on before insert or update of open_on on public.couple_letters
  for each row execute function private.check_letter_open_on();

-- The notice waits for the day.
create or replace function private.notify_sent_letter()
returns trigger language plpgsql security definer set search_path to '' as $$
declare peer uuid;
begin
 if new.status <> 'sent' then return new; end if;
 if tg_op='UPDATE' and old.status='sent' then return new; end if;
 if new.open_on is not null and new.open_on > current_date then return new; end if;
 select user_id into peer from public.space_members
  where space_id=new.space_id and user_id<>new.author_id limit 1;
 if peer is not null then
  insert into public.space_notifications
   (space_id,recipient_id,actor_id,kind,object_kind,object_id,headline)
  values(new.space_id,peer,new.author_id,'letter','letter',new.id,left(new.title,180))
  on conflict do nothing;
 end if;
 return new;
end; $$;

create or replace function private.deliver_scheduled_letters()
returns integer language plpgsql security definer set search_path to '' as $$
declare r record; peer uuid; n int:=0;
begin
  for r in select * from public.couple_letters
    where status='sent' and open_on is not null and open_on <= current_date and delivered_at is null loop
    select user_id into peer from public.space_members
     where space_id=r.space_id and user_id<>r.author_id limit 1;
    if peer is not null then
      insert into public.space_notifications
       (space_id,recipient_id,actor_id,kind,object_kind,object_id,headline)
      values(r.space_id,peer,r.author_id,'letter','letter',r.id,left(r.title,180))
      on conflict do nothing;
    end if;
    update public.couple_letters set delivered_at=now() where id=r.id;
    n:=n+1;
  end loop;
  return n;
end $$;
revoke all on function private.deliver_scheduled_letters() from public, anon, authenticated;
do $$ begin perform cron.unschedule('onespace-letter-delivery'); exception when others then null; end $$;
select cron.schedule('onespace-letter-delivery','11 * * * *','select private.deliver_scheduled_letters();');

-- The partner may see that a letter is waiting (no title, no words).
create or replace function public.sealed_letters()
returns table(id uuid, author_id uuid, open_on date, sent_at timestamptz)
language sql stable security definer set search_path to '' as $$
  select l.id, l.author_id, l.open_on, l.sent_at from public.couple_letters l
   where l.status='sent' and l.open_on > current_date and l.author_id <> auth.uid()
     and private.is_space_member(l.space_id)
   order by l.open_on;
$$;
revoke all on function public.sealed_letters() from public, anon;
grant execute on function public.sealed_letters() to authenticated;

alter table public.memories add column if not exists place text check (char_length(place) <= 160);
grant insert (place) on public.memories to authenticated;
grant update (place) on public.memories to authenticated;

-- Sent letters stay unchangeable, except the delivery stamp set on the day.
create or replace function private.enforce_couple_letter_state()
returns trigger language plpgsql security definer set search_path to '' as $$
declare parent_status text;
begin
 if tg_op='INSERT' then
   if new.reply_to is not null then
     select l.status into parent_status from public.couple_letters l
      where l.id=new.reply_to and l.space_id=new.space_id;
     if parent_status is distinct from 'sent' then
       raise exception 'Replies must reference a sent letter in this space';
     end if;
   end if;
   if new.status='sent' then
     if length(btrim(new.body))=0 then raise exception 'A letter needs a message to send'; end if;
     new.sent_at:=now();
   else
     new.sent_at:=null;
   end if;
 else
   if old.status='sent' and (to_jsonb(new)-'delivered_at'-'updated_at') = (to_jsonb(old)-'delivered_at'-'updated_at') then
     return new;
   end if;
   if old.status<>'draft' or new.space_id<>old.space_id
      or new.author_id<>old.author_id or new.id<>old.id
      or new.created_at<>old.created_at then
     raise exception 'Sent letters are immutable';
   end if;
   if new.reply_to is distinct from old.reply_to then
     raise exception 'Cannot change letter reply context';
   end if;
   if new.status='sent' then
     if length(btrim(new.body))=0 then raise exception 'A letter needs a message to send'; end if;
     new.sent_at:=now();
   else
     new.sent_at:=null;
   end if;
 end if;
 new.updated_at:=now();
 return new;
end;$$;
