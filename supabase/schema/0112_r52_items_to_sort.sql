-- OneSpace R52 - Share-in 2.0 and "Items to sort" (spec section 4, backlog B-16).
-- Non-destructive: one new table with RLS, history coverage, and a badge count in onespace_today.

create table if not exists public.items_to_sort (
  id uuid primary key default gen_random_uuid(),
  space_id uuid not null references public.spaces(id) on delete cascade,
  created_by uuid not null default auth.uid() references auth.users(id) on delete cascade,
  title text not null check (char_length(btrim(title)) between 1 and 180),
  link text check (link is null or char_length(link) <= 1800),
  note text check (note is null or char_length(note) <= 5000),
  -- Private to the person who saved it by default; may be switched to Shared.
  visibility text not null default 'private' check (visibility in ('private','shared')),
  sorted_at timestamptz,
  sorted_to text check (sorted_to is null or char_length(sorted_to) <= 40),
  archived_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
comment on table public.items_to_sort is
 'R52: the share-in tray ("Items to sort"). Private by default; Remove = archived_at; Sort moves the content into a real item and stamps sorted_at.';
create index if not exists items_to_sort_owner_open on public.items_to_sort(created_by, created_at desc)
  where sorted_at is null and archived_at is null;
create index if not exists items_to_sort_space on public.items_to_sort(space_id);

alter table public.items_to_sort enable row level security;

drop policy if exists "Read my items to sort and shared ones" on public.items_to_sort;
create policy "Read my items to sort and shared ones" on public.items_to_sort for select to authenticated
 using (created_by = (select auth.uid())
   or (visibility = 'shared' and private.is_space_member(space_id)));
drop policy if exists "Add my own items to sort" on public.items_to_sort;
create policy "Add my own items to sort" on public.items_to_sort for insert to authenticated
 with check (created_by = (select auth.uid()) and private.is_space_member(space_id));
drop policy if exists "Update my items to sort or shared ones" on public.items_to_sort;
create policy "Update my items to sort or shared ones" on public.items_to_sort for update to authenticated
 using (created_by = (select auth.uid())
   or (visibility = 'shared' and private.is_space_member(space_id)))
 with check (private.is_space_member(space_id)
   and (created_by = (select auth.uid()) or visibility = 'shared'));
-- No delete: Remove keeps the record (spec 2.6).
grant select, insert, update on public.items_to_sort to authenticated;
revoke delete on public.items_to_sort from authenticated, anon;

create or replace function private.touch_items_to_sort()
returns trigger language plpgsql set search_path to '' as $$
begin new.updated_at:=now(); return new; end $$;
drop trigger if exists items_to_sort_touch on public.items_to_sort;
create trigger items_to_sort_touch before update on public.items_to_sort
 for each row execute function private.touch_items_to_sort();

-- Change log coverage (spec 4.3: Sort, Remove, Change log).
alter table public.record_action_history drop constraint if exists record_action_history_record_kind_check,
 add constraint record_action_history_record_kind_check check (record_kind = any (array[
  'note','task','goal','memory','event','reminder','occasion','experience','trip','contact',
  'checkin','checkin_request','experience_comment','sort_item']));
do $m$
declare d text:=pg_get_functiondef('private.audit_additional_record_action()'::regprocedure);
 o text:=$o$when 'partner_checkin_requests' then 'checkin_request'$o$;
 n text:=$n$when 'partner_checkin_requests' then 'checkin_request' when 'items_to_sort' then 'sort_item'$n$;
begin
 if position('items_to_sort' in d)>0 then return; end if;
 if position(o in d)=0 then raise exception 'pattern not found'; end if;
 execute replace(d,o,n);
end $m$;
drop trigger if exists r52_sort_item_actions on public.items_to_sort;
create trigger r52_sort_item_actions after insert or update on public.items_to_sort
 for each row execute function private.audit_additional_record_action();

drop policy if exists "Read history of visible items to sort" on public.record_action_history;
create policy "Read history of visible items to sort" on public.record_action_history for select to authenticated
 using (record_kind = 'sort_item' and exists (select 1 from public.items_to_sort i
   where i.id = record_action_history.record_id and i.space_id = record_action_history.space_id));

-- Today badge: items waiting to be sorted that I can see.
do $m$
declare d text:=pg_get_functiondef('public.onespace_today(date)'::regprocedure);
 o text:=$o$'notifications',(select count(*) from unread)),$o$;
 n text:=$n$'notifications',(select count(*) from unread),
     'items_to_sort',(select count(*) from public.items_to_sort i
        where i.space_id=(snap->>'space_id')::uuid and i.sorted_at is null and i.archived_at is null)),$n$;
begin
 if position('items_to_sort' in d)>0 then return; end if;
 if position(o in d)=0 then raise exception 'pattern not found'; end if;
 execute replace(d,o,n);
end $m$;
