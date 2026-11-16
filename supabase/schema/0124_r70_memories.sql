-- R70 (Ahmed's Memories notes). Non-destructive.
-- 1. More story layouts (carousel, mosaic, film strip, scattered, timeline).
-- 2. Scrapbook: 18 more page designs, a 4th photo slot, and pages can be
--    removed (the remaining pages close the gap; the last page stays).

alter table public.memories drop constraint if exists memories_photo_layout_check;
alter table public.memories add constraint memories_photo_layout_check check (photo_layout in
  ('grid','feature','polaroid','overlap','carousel','mosaic','film','scatter','timeline'));

alter table public.scrapbook_pages
  add column if not exists photo_4_id uuid references public.memory_photos(id) on delete set null;
grant insert (photo_4_id) on public.scrapbook_pages to authenticated;
grant update (photo_4_id) on public.scrapbook_pages to authenticated;

alter table public.scrapbook_pages drop constraint if exists scrapbook_pages_template_key_check;
alter table public.scrapbook_pages add constraint scrapbook_pages_template_key_check check (template_key in (
  'polaroid_letters','our_adventures','little_moments','milestone_story',
  'first_date','date_night','anniversary_gold','birthday_bash','eid_joy','ramadan_nights',
  'family_day','our_home','miles_apart','little_one','cooked_together','love_note',
  'film_strip','postcard','year_in_review','four_seasons','graduation','wedding_day'));

create or replace function public.create_scrapbook(p_space_id uuid, p_title text, p_template_key text,
  p_visibility text default 'shared', p_memory_date date default current_date)
returns uuid language plpgsql security definer set search_path to '' as $$
declare result uuid; who uuid:=auth.uid();
begin
 if who is null or p_space_id is null or not private.is_space_member(p_space_id)
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
 insert into public.memories(space_id,created_by,title,body,memory_date,visibility,memory_type,photo_layout)
 values(p_space_id,who,btrim(p_title),'',p_memory_date,p_visibility,'scrapbook','grid')
 returning id into result;
 insert into public.scrapbook_pages(memory_id,page_order,template_key,created_by,title)
 values(result,0,p_template_key,who,btrim(p_title));
 return result;
end $$;

-- Remove one page; the others move up so there is no gap. The last page stays.
create or replace function public.remove_scrapbook_page(p_page_id uuid)
returns void language plpgsql security definer set search_path to '' as $$
declare v_memory uuid; v_count int; r record; i int:=0;
begin
  select memory_id into v_memory from public.scrapbook_pages where id=p_page_id;
  if v_memory is null then raise exception 'Page not found'; end if;
  if not private.may_edit_scrapbook(v_memory, auth.uid()) then
    raise exception 'Only the scrapbook''s collaborators can remove pages';
  end if;
  select count(*) into v_count from public.scrapbook_pages where memory_id=v_memory;
  if v_count <= 1 then raise exception 'A scrapbook keeps at least one page'; end if;
  delete from public.scrapbook_pages where id=p_page_id;
  for r in select id from public.scrapbook_pages where memory_id=v_memory order by page_order loop
    update public.scrapbook_pages set page_order=i where id=r.id and page_order<>i;
    i:=i+1;
  end loop;
end $$;
revoke all on function public.remove_scrapbook_page(uuid) from public, anon;
grant execute on function public.remove_scrapbook_page(uuid) to authenticated;
