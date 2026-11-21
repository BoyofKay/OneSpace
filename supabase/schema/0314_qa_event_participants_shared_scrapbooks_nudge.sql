-- QA 0314 (Amr, 21 Nov afternoon). QA only; never apply to Production.
--  1. Calendar: who an event is for (participants) is independent of who can
--     see it. A private (Only me) event may be for me, for both of us or for
--     my current partner. A partner's account deletion clears the
--     participant instead of deleting my private event.
--  2. Shared scrapbooks are editable by both partners, like every shared
--     item. The invitation step is no longer needed.
--  3. Nudge my partner about a shared memory or scrapbook (notification).

-- 1. Event participants ----------------------------------------------------
create or replace function private.validate_event_person()
returns trigger language plpgsql set search_path to '' as $function$
begin
 if new.private_space_id is not null then
   if new.space_id is not null or new.created_by is distinct from new.private_space_id
     or new.visibility<>'private' then
       raise exception 'Personal calendar event must belong to its account owner';
   end if;
   -- For me, for both of us, or for my current partner (checked when chosen).
   if new.for_user_id is not null and new.for_user_id is distinct from new.created_by
      and (tg_op='INSERT' or new.for_user_id is distinct from old.for_user_id)
      and not private.qa_is_current_partner(new.for_user_id) then
     raise exception 'The selected person is not your current partner';
   end if;
   return new;
 end if;
 if new.for_user_id is not null and not exists(
    select 1 from public.space_members
    where space_id=new.space_id and user_id=new.for_user_id
 ) then raise exception 'The selected person is not part of this space'; end if;
 return new;
end; $function$;

drop policy if exists "QA account owner creates personal events" on public.space_events;
create policy "QA account owner creates personal events" on public.space_events
 for insert to authenticated with check (
  private_space_id=(select auth.uid()) and created_by=(select auth.uid())
  and visibility='private' and space_id is null);
drop policy if exists "QA account owner edits personal events" on public.space_events;
create policy "QA account owner edits personal events" on public.space_events
 for update to authenticated
 using (private_space_id=(select auth.uid()) and created_by=(select auth.uid())
  and visibility='private' and space_id is null)
 with check (private_space_id=(select auth.uid()) and created_by=(select auth.uid())
  and visibility='private' and space_id is null);
drop policy if exists "QA account owner reads personal events" on public.space_events;
create policy "QA account owner reads personal events" on public.space_events
 for select to authenticated using (
  private_space_id=(select auth.uid()) and created_by=(select auth.uid())
  and visibility='private' and space_id is null);

alter table public.space_events drop constraint if exists space_events_for_user_id_fkey;
alter table public.space_events add constraint space_events_for_user_id_fkey
 foreign key (for_user_id) references auth.users(id) on delete set null not valid;

-- 2. Shared scrapbooks: both partners edit ------------------------------------
create or replace function private.may_edit_scrapbook(p_memory uuid, p_user uuid)
returns boolean language sql stable security definer set search_path to '' as $function$
 select exists(select 1 from public.memories m
  where m.id=p_memory and m.memory_type='scrapbook' and m.archived_at is null
   and (
    (m.private_space_id is not null and m.private_space_id=p_user
       and m.created_by=p_user and m.space_id is null and m.visibility='private')
    or
    (m.private_space_id is null and m.space_id is not null
       and exists(select 1 from public.space_members sm
                  where sm.space_id=m.space_id and sm.user_id=p_user)
       and (m.created_by=p_user or m.visibility='shared'))
   ))
$function$;

-- 3. Nudge my partner about a shared memory -------------------------------------
create or replace function public.nudge_partner_about_memory(p_memory_id uuid)
returns void language plpgsql security definer set search_path to '' as $function$
declare me uuid:=auth.uid(); m record; partner uuid;
begin
 select id,space_id,title,memory_type,visibility,archived_at into m
 from public.memories where id=p_memory_id;
 if me is null or not found or m.space_id is null or m.visibility<>'shared'
    or m.archived_at is not null or not private.is_space_member(m.space_id) then
  raise exception 'Only a shared memory can be sent to your partner' using errcode='42501';
 end if;
 select user_id into partner from public.space_members
  where space_id=m.space_id and user_id<>me order by joined_at limit 1;
 if partner is null then raise exception 'Your partner has not joined yet'; end if;
 if exists(select 1 from public.space_notifications n
   where n.recipient_id=partner and n.kind='message' and n.object_id=p_memory_id
     and n.actor_id=me and n.created_at>now()-interval '1 minute') then
  raise exception 'You just nudged your partner. Try again in a minute.';
 end if;
 insert into public.space_notifications(space_id,recipient_id,actor_id,kind,object_kind,
   object_id,headline,detail,generated_automatically)
 values(m.space_id,partner,me,'message',
   case when m.memory_type='scrapbook' then 'scrapbook' else 'memory' end,
   p_memory_id,left(coalesce(nullif(btrim(m.title),''),'Our memory'),180),
   'Would love you to add your part to this memory',true)
 on conflict(recipient_id,kind,object_id) do update set
   actor_id=excluded.actor_id, headline=excluded.headline, detail=excluded.detail,
   created_at=now(), read_at=null;
end $function$;
revoke all on function public.nudge_partner_about_memory(uuid) from public,anon,authenticated;
grant execute on function public.nudge_partner_about_memory(uuid) to authenticated;
