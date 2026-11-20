-- Reconciled 2026-11-20: applied to QA (ugwrpeduzyzrujkizqfo) on 2026-11-20 from
-- feat-qa-personal-activities-memories-20261120:supabase/schema/0241_qa_private_memory_media_service_role_guard.sql (original number 0241). Kept verbatim so the
-- repository replays to the live QA schema. QA only; never apply to Production.
-- QA: Physical media rows cannot attach to personal Memory roots until
-- account-owned Storage and delete/revoke semantics are verified.
-- A trigger is essential: service_role bypasses RLS, not constraints/triggers.
create or replace function private.qa_block_personal_memory_media()
returns trigger language plpgsql set search_path='' as $fn$
begin
 if exists(
   select 1 from public.memories m
   where m.id=new.memory_id and m.private_space_id is not null) then
   raise exception 'Personal Memory media storage is not enabled'
    using errcode='42501';
 end if;
 return new;
end $fn$;
revoke all on function private.qa_block_personal_memory_media()
 from public,anon,authenticated;
drop trigger if exists qa_block_private_memory_photo on public.memory_photos;
create trigger qa_block_private_memory_photo
 before insert or update on public.memory_photos
 for each row execute function private.qa_block_personal_memory_media();
drop trigger if exists qa_block_private_scrapbook_page on public.scrapbook_pages;
create trigger qa_block_private_scrapbook_page
 before insert or update on public.scrapbook_pages
 for each row execute function private.qa_block_personal_memory_media();
