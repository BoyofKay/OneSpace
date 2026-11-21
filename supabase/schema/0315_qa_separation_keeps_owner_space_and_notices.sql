-- QA 0315 (Amr, 21 Nov 16:54 Riyadh). QA only; never apply to Production.
-- After a separation:
--  * Partner leaves      -> the owner keeps a (fresh, empty) shared space and
--                           gets a notice; the leaver gets the 3 options + notice.
--  * Owner removes partner -> same: owner keeps a space, removed partner gets
--                           the 3 options; both get a notice.
--  * Owner deletes space -> neither keeps a space; both get a notice.
--  * Account deletion    -> if the remaining partner owns the space they keep it;
--                           otherwise they get the 3 options. They get a notice.
-- Notices live in public.account_notices (not tied to a space, so they survive
-- the space deletion) and show as a fixed banner on Today until dismissed.

create table if not exists public.account_notices (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null references auth.users(id) on delete cascade,
 kind text not null check (kind in ('partner_left','you_left','partner_removed_you',
   'you_removed_partner','space_deleted','you_deleted_space','partner_deleted_account')),
 title text not null,
 body text not null,
 created_at timestamptz not null default now(),
 dismissed_at timestamptz
);
create index if not exists account_notices_open on public.account_notices(user_id)
 where dismissed_at is null;
alter table public.account_notices enable row level security;
drop policy if exists "Own notices" on public.account_notices;
create policy "Own notices" on public.account_notices for select to authenticated
 using (user_id=(select auth.uid()));
drop policy if exists "Dismiss own notices" on public.account_notices;
create policy "Dismiss own notices" on public.account_notices for update to authenticated
 using (user_id=(select auth.uid())) with check (user_id=(select auth.uid()));
revoke all on public.account_notices from public,anon,authenticated;
grant select on public.account_notices to authenticated;
grant update(dismissed_at) on public.account_notices to authenticated;

-- Keep the audited separation transaction exactly as it is, and wrap it.
do $r$ begin
 if not exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='private' and p.proname='qa_close_relationship_v2_core') then
  alter function private.qa_close_relationship_v2(uuid,text,text)
   rename to qa_close_relationship_v2_core;
 end if;
end $r$;
revoke all on function private.qa_close_relationship_v2_core(uuid,text,text)
 from public,anon,authenticated;

create or replace function private.qa_first_name(p_user uuid, p_fallback text)
returns text language sql stable security definer set search_path to '' as $$
 select coalesce(nullif(split_part(btrim(coalesce(
   (select p.display_name from public.profiles p where p.id=p_user),'')),' ',1),''),p_fallback)
$$;
revoke all on function private.qa_first_name(uuid,text) from public,anon,authenticated;

create or replace function private.qa_close_relationship_v2(
 p_space uuid, p_action text, p_confirmation text)
returns jsonb language plpgsql security definer set search_path to '' as $function$
declare me uuid:=auth.uid(); owner_id uuid; guest uuid; members int;
 owner_name text; guest_name text; by_deletion boolean; result jsonb;
 kept uuid; new_space uuid;
 safe constant text:=' Shared items were removed. Private items are safe.';
begin
 select s.created_by into owner_id from public.spaces s where s.id=p_space;
 select count(*) into members from public.space_members m where m.space_id=p_space;
 select m.user_id into guest from public.space_members m
  where m.space_id=p_space and m.user_id<>owner_id limit 1;

 result:=private.qa_close_relationship_v2_core(p_space,p_action,p_confirmation);

 -- Only a real pair has someone to tell.
 if members<>2 or guest is null or owner_id is null then return result; end if;
 owner_name:=private.qa_first_name(owner_id,'Your partner');
 guest_name:=private.qa_first_name(guest,'Your partner');
 -- Closed on behalf of an account whose deletion is due.
 by_deletion:=exists(select 1 from public.account_deletion_requests r
   where r.user_id=me and r.cancelled_at is null and r.completed_at is null
     and r.purge_after<=now());

 if by_deletion then
  if me=guest then
   kept:=owner_id;
   insert into public.account_notices(user_id,kind,title,body) values(owner_id,
    'partner_deleted_account',guest_name||' deleted their account',
    'Your space is still here, ready for a new partner.'||safe);
  else
   insert into public.account_notices(user_id,kind,title,body) values(guest,
    'partner_deleted_account',owner_name||' deleted their account',
    'Their shared space was closed. You can join a partner, invite one, or create your own space.'||safe);
  end if;
 elsif p_action='leave_space' then
  kept:=owner_id;
  insert into public.account_notices(user_id,kind,title,body) values
   (owner_id,'partner_left',guest_name||' left your space',
    'Your space is still here, ready for a new partner.'||safe),
   (guest,'you_left','You left '||owner_name||'''s space',
    'You can join a partner, invite one, or create your own space.'||safe);
 elsif p_action='remove_partner' then
  kept:=owner_id;
  insert into public.account_notices(user_id,kind,title,body) values
   (owner_id,'you_removed_partner','You removed '||guest_name,
    'Your space is still here, ready for a new partner.'||safe),
   (guest,'partner_removed_you',owner_name||' removed you from their space',
    'You can join a partner, invite one, or create your own space.'||safe);
 elsif p_action='delete_space' then
  insert into public.account_notices(user_id,kind,title,body) values
   (owner_id,'you_deleted_space','You deleted your shared space',
    'You can invite a partner, join one, or create a new space.'||safe),
   (guest,'space_deleted',owner_name||' deleted the shared space',
    'You can join a partner, invite one, or create your own space.'||safe);
 end if;

 -- The owner keeps a space (fresh and empty) so nothing changes for them,
 -- unless their own account is being deleted.
 if kept is not null and not private.qa_account_pending_delete(kept)
    and not exists(select 1 from public.space_members m join public.spaces s on s.id=m.space_id
                   where m.user_id=kept and s.personal_owner is null) then
  insert into public.spaces(created_by) values(kept) returning id into new_space;
  insert into public.space_members(space_id,user_id) values(new_space,kept);
  result:=result||jsonb_build_object('owner_space_kept',new_space);
 end if;
 return result;
end $function$;
revoke all on function private.qa_close_relationship_v2(uuid,text,text) from public,anon,authenticated;
grant execute on function private.qa_close_relationship_v2(uuid,text,text) to service_role;
grant execute on function private.qa_close_relationship_v2_core(uuid,text,text) to service_role;
