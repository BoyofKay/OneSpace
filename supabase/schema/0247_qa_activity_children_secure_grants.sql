-- Reconciled 2026-11-20: applied to QA (ugwrpeduzyzrujkizqfo) on 2026-11-20 from
-- feat-qa-personal-activities-memories-20261120:supabase/schema/0239_qa_activity_children_secure_grants.sql (original number 0239). Kept verbatim so the
-- repository replays to the live QA schema. QA only; never apply to Production.
-- QA: Explicit grants only on conversation/step data already protected by
-- parent-aware RLS. Do not grant memory_photos or shared media writes here.
grant insert on public.activity_comments to authenticated;
grant insert,update on public.activity_components to authenticated;
create or replace function private.qa_lock_activity_component_parent()
returns trigger language plpgsql set search_path='' as $fn$
begin
 if current_user='authenticated' and
  (new.activity_id is distinct from old.activity_id
    or new.created_by is distinct from old.created_by) then
   raise exception 'An Activity component cannot change parent or creator'
     using errcode='42501';
 end if;
 return new;
end $fn$;
revoke all on function private.qa_lock_activity_component_parent()
 from public,anon,authenticated;
drop trigger if exists qa_lock_activity_component_parent on public.activity_components;
create trigger qa_lock_activity_component_parent
 before update on public.activity_components for each row
 execute function private.qa_lock_activity_component_parent();
