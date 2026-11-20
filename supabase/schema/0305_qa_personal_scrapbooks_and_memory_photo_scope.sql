-- QA 0305: personal (account-owned) scrapbooks, and keep Memory photo bytes
-- in the bucket that matches their Memory's scope.
--
-- Before this file, in QA:
--  * create_scrapbook(p_visibility=>'private') inserted a couple-scoped private
--    Memory, which route_record_scope refuses ("Update your app ..."), so no
--    private scrapbook could be created, and a solo account could not create one.
--  * scrapbook_pages for account-owned Memories were blocked outright.
--  * the legacy shared-bucket and memory_photos policies still let an owner
--    attach a personal Memory's photo to the SHARED bucket (e.g. older app).
--  * validate_scrapbook_page_photos ignored photo_4_id.
-- QA only; never apply to Production.

-- 1. Scrapbook creation follows the ADR scopes.
create or replace function public.create_scrapbook(
  p_space_id uuid, p_title text, p_template_key text,
  p_visibility text default 'shared', p_memory_date date default current_date)
returns uuid language plpgsql security definer set search_path to ''
as $function$
declare result uuid; who uuid:=auth.uid();
begin
 if who is null
    or char_length(btrim(coalesce(p_title,''))) not between 1 and 120
    or p_template_key not in (
     'polaroid_letters','our_adventures','little_moments','milestone_story',
     'first_date','date_night','anniversary_gold','birthday_bash','eid_joy','ramadan_nights',
     'family_day','our_home','miles_apart','little_one','cooked_together','love_note',
     'film_strip','postcard','year_in_review','four_seasons','graduation','wedding_day')
    or p_visibility not in ('shared','private')
    or p_memory_date not between date '1900-01-01' and date '2100-12-31' then
   raise exception 'Invalid scrapbook request';
 end if;
 if p_visibility='private' then
   -- Private scrapbooks always belong to the account, never to a couple.
   if not exists(select 1 from public.user_private_spaces s where s.owner_id=who) then
     raise exception 'Personal space unavailable' using errcode='42501';
   end if;
   insert into public.memories(private_space_id,space_id,created_by,title,body,
     memory_date,visibility,memory_type,photo_layout)
   values(who,null,who,btrim(p_title),'',p_memory_date,'private','scrapbook','grid')
   returning id into result;
 else
   if p_space_id is null or not private.is_space_member(p_space_id)
      or (select count(*) from public.space_members m where m.space_id=p_space_id)<>2 then
     raise exception 'Join a partner before creating a shared scrapbook'
       using errcode='42501';
   end if;
   insert into public.memories(space_id,created_by,title,body,memory_date,
     visibility,memory_type,photo_layout)
   values(p_space_id,who,btrim(p_title),'',p_memory_date,'shared','scrapbook','grid')
   returning id into result;
 end if;
 insert into public.scrapbook_pages(memory_id,page_order,template_key,created_by,title)
 values(result,0,p_template_key,who,btrim(p_title));
 return result;
end $function$;
revoke all on function public.create_scrapbook(uuid,text,text,text,date) from public,anon;
grant execute on function public.create_scrapbook(uuid,text,text,text,date) to authenticated;

-- 2. Who may edit pages: the owner of a personal scrapbook, or (shared) the
--    creator / an accepted invitee who is still in that couple.
create or replace function private.may_edit_scrapbook(p_memory uuid, p_user uuid)
returns boolean language sql stable security definer set search_path to ''
as $function$
 select exists(select 1 from public.memories m
  where m.id=p_memory and m.memory_type='scrapbook' and m.archived_at is null
   and (
    (m.private_space_id is not null and m.private_space_id=p_user
       and m.created_by=p_user and m.space_id is null and m.visibility='private')
    or
    (m.private_space_id is null and m.space_id is not null
       and exists(select 1 from public.space_members sm
                  where sm.space_id=m.space_id and sm.user_id=p_user)
       and (m.created_by=p_user or (
         m.visibility='shared' and exists(
           select 1 from public.scrapbook_invites i
           where i.memory_id=m.id and i.invited_user_id=p_user
             and i.status='accepted'))))
   ))
$function$;
revoke all on function private.may_edit_scrapbook(uuid,uuid) from public,anon;
grant execute on function private.may_edit_scrapbook(uuid,uuid) to authenticated;

-- 3. Personal scrapbook pages are now supported (owner only, via may_edit).
drop policy if exists "QA personal memories no scrapbook page writes" on public.scrapbook_pages;
drop policy if exists "QA personal memories no scrapbook page updates" on public.scrapbook_pages;
drop trigger if exists qa_block_private_scrapbook_page on public.scrapbook_pages;

-- 4. Every photo slot (including the fourth) must be a live photo of this Memory.
create or replace function private.validate_scrapbook_page_photos()
returns trigger language plpgsql set search_path to ''
as $function$
declare requested uuid; ok boolean;
begin
 if tg_op='UPDATE' and new.memory_id<>old.memory_id then
   raise exception 'Cannot transfer a scrapbook page to another memory';
 end if;
 for requested in select distinct unnest(array[
   new.photo_1_id,new.photo_2_id,new.photo_3_id,new.photo_4_id
 ]) loop
  if requested is not null then
    select exists(select 1 from public.memory_photos p
      where p.id=requested and p.memory_id=new.memory_id and p.archived_at is null)
    into ok;
    if not ok then raise exception 'Scrapbook photo is not part of this memory';end if;
  end if;
 end loop;
 new.updated_at=now();
 new.updated_by=auth.uid();
 return new;
end $function$;

-- 5. Legacy photo policies cover couple-scoped Memories only, in the shared bucket.
drop policy if exists "Owner can add photo to editable memory" on public.memory_photos;
create policy "Owner can add photo to editable memory" on public.memory_photos
 for insert to authenticated
 with check (created_by=(select auth.uid())
   and storage_bucket_id='onespace-memory-photos'
   and exists(select 1 from public.memories m
     where m.id=memory_photos.memory_id and m.private_space_id is null
       and (m.visibility='shared' or m.created_by=(select auth.uid()))));
drop policy if exists "Member can edit photo of collaborative memory" on public.memory_photos;
create policy "Member can edit photo of collaborative memory" on public.memory_photos
 for update to authenticated
 using (exists(select 1 from public.memories m
     where m.id=memory_photos.memory_id and m.private_space_id is null
       and (m.visibility='shared' or m.created_by=(select auth.uid()))))
 with check (storage_bucket_id='onespace-memory-photos'
   and exists(select 1 from public.memories m
     where m.id=memory_photos.memory_id and m.private_space_id is null
       and (m.visibility='shared' or m.created_by=(select auth.uid()))));

drop policy if exists "Upload own photo under editable memory" on storage.objects;
create policy "Upload own photo under editable memory" on storage.objects
 for insert to authenticated
 with check (bucket_id='onespace-memory-photos'
   and split_part(name,'/',2)=(select auth.uid())::text
   and exists(select 1 from public.memories m
     where m.id=private.memory_id_from_object_path(objects.name)
       and m.private_space_id is null
       and (m.visibility='shared' or m.created_by=(select auth.uid()))));
drop policy if exists "Remove only own unreferenced memory upload" on storage.objects;
create policy "Remove only own unreferenced memory upload" on storage.objects
 for delete to authenticated
 using (bucket_id='onespace-memory-photos'
   and split_part(name,'/',2)=(select auth.uid())::text
   and not exists(select 1 from public.memory_photos p where p.object_path=objects.name)
   and exists(select 1 from public.memories m
     where m.id=private.memory_id_from_object_path(objects.name)
       and m.private_space_id is null
       and (m.visibility='shared' or m.created_by=(select auth.uid()))));
