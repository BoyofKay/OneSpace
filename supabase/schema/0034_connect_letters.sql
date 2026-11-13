-- Connect: actual private draft and shared correspondence for a couple.
create table public.couple_letters (
 id uuid primary key default gen_random_uuid(),
 space_id uuid not null references public.spaces(id) on delete cascade,
 author_id uuid not null default auth.uid() references auth.users(id),
 title text not null check(char_length(btrim(title)) between 1 and 160),
 body text not null default '' check(char_length(body) <= 16000),
 status text not null default 'draft' check(status in ('draft','sent')),
 reply_to uuid,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 sent_at timestamptz,
 unique(space_id,id),
 foreign key(space_id,reply_to) references public.couple_letters(space_id,id)
);
create index couple_letters_feed_idx on public.couple_letters(space_id,sent_at desc,updated_at desc);
create index couple_letters_drafts_idx on public.couple_letters(author_id,updated_at desc)
 where status='draft';
alter table public.couple_letters enable row level security;
create policy "Letters visible to authorized partners" on public.couple_letters
 for select to authenticated using(
 private.is_space_member(space_id) and
 (status='sent' or author_id=(select auth.uid()))
 );
create policy "Authors create drafts or sent letters" on public.couple_letters
 for insert to authenticated with check(
  author_id=(select auth.uid()) and private.is_space_member(space_id)
  and (reply_to is null or exists(
    select 1 from public.couple_letters parent
    where parent.id=reply_to and parent.space_id=space_id
      and parent.status='sent'
  ))
 );
create policy "Authors edit only their drafts" on public.couple_letters
 for update to authenticated using(
  author_id=(select auth.uid()) and status='draft'
  and private.is_space_member(space_id)
 ) with check(
  author_id=(select auth.uid()) and private.is_space_member(space_id)
 );
create policy "Authors may delete their drafts" on public.couple_letters
 for delete to authenticated using(
  author_id=(select auth.uid()) and status='draft'
  and private.is_space_member(space_id)
 );
create function private.enforce_couple_letter_state() returns trigger
 language plpgsql set search_path='' as $$
begin
 if tg_op='INSERT' then
   if new.status='sent' then
     if length(btrim(new.body))=0 then
       raise exception 'A letter needs a message to send';
     end if;
     new.sent_at:=now();
   else
     new.sent_at:=null;
   end if;
 else
   if old.status<>'draft' or new.space_id<>old.space_id
      or new.author_id<>old.author_id or new.id<>old.id
      or new.created_at<>old.created_at then
     raise exception 'Sent letters are immutable';
   end if;
   if new.status='sent' then
     if length(btrim(new.body))=0 then
       raise exception 'A letter needs a message to send';
     end if;
     new.sent_at:=now();
   else
     new.sent_at:=null;
   end if;
   if new.reply_to is distinct from old.reply_to then
     raise exception 'Cannot change letter reply context';
   end if;
 end if;
 new.updated_at:=now();
 return new;
end;$$;
create trigger enforce_couple_letter_state before insert or update
 on public.couple_letters for each row execute function private.enforce_couple_letter_state();

create table public.couple_letter_reads (
 letter_id uuid not null references public.couple_letters(id) on delete cascade,
 reader_id uuid not null default auth.uid() references auth.users(id),
 opened_at timestamptz not null default now(),
 primary key(letter_id,reader_id)
);
alter table public.couple_letter_reads enable row level security;
create policy "Read receipt visible to both letter partners" on public.couple_letter_reads
 for select to authenticated using(
  exists(select 1 from public.couple_letters l
   where l.id=letter_id and l.status='sent'
   and private.is_space_member(l.space_id))
 );
create policy "Only recipient can mark own read" on public.couple_letter_reads
 for insert to authenticated with check(
  reader_id=(select auth.uid()) and exists(
   select 1 from public.couple_letters l
   where l.id=letter_id and l.status='sent'
    and l.author_id<>(select auth.uid())
    and private.is_space_member(l.space_id))
 );
revoke all on public.couple_letters,public.couple_letter_reads from public,anon,authenticated;
grant select,insert,update,delete on public.couple_letters to authenticated;
grant select,insert on public.couple_letter_reads to authenticated;
