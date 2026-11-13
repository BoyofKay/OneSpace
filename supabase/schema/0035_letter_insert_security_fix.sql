-- Avoid self-referencing RLS policy recursion. The composite space FK
-- enforces same-space replies, and the trigger checks parent status.
drop policy "Authors create drafts or sent letters" on public.couple_letters;
create policy "Authors create letters in their space" on public.couple_letters
 for insert to authenticated with check(
   author_id=(select auth.uid()) and private.is_space_member(space_id)
 );
create or replace function private.enforce_couple_letter_state() returns trigger
language plpgsql security definer set search_path='' as $$
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
   if new.reply_to is distinct from old.reply_to then
     raise exception 'Cannot change letter reply context';
   end if;
   if new.status='sent' then
     if length(btrim(new.body))=0 then
       raise exception 'A letter needs a message to send';
     end if;
     new.sent_at:=now();
   else
     new.sent_at:=null;
   end if;
 end if;
 new.updated_at:=now();
 return new;
end;$$;
