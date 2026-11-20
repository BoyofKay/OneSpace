-- QA account-owned Activity + Memory metadata cutover. No migration of
-- historical records or attachment bytes; those remain separate gates.
-- This fixes the old private -> legacy solo spaces trigger route.
CREATE OR REPLACE FUNCTION private.route_record_scope()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_me uuid:=auth.uid();
  v_target uuid;
  v_couple uuid;
  v_personal_target boolean;
begin
  -- QA: these two modules have account-owned roots, never legacy solo spaces.
  -- Refuse stale-client private writes into the couple scope.
  if tg_table_name in ('activities','memories') then
    if new.private_space_id is not null then
      if new.private_space_id is distinct from v_me
        or new.created_by is distinct from v_me
        or new.space_id is not null or new.visibility<>'private' then
        raise exception 'Personal object ownership/scope mismatch' using errcode='42501';
      end if;
      return new;
    end if;
    if new.visibility='private' and v_me is not null
      and (tg_op='INSERT' or old.private_space_id is not null) then
      raise exception 'Update your app to save private data securely'
        using errcode='42501';
    end if;
  end if;
  if v_me is null or new.space_id is null then return new; end if;
  if tg_op='UPDATE'
     and new.visibility is not distinct from old.visibility
     and new.space_id is not distinct from old.space_id then
    return new;
  end if;

  if new.visibility='private' then
    if tg_op='UPDATE' and old.created_by is distinct from v_me then
      raise exception 'Only the person who created this can make it private'
        using errcode='42501';
    end if;
    if new.created_by is distinct from v_me then
      raise exception 'Private records belong to the person who creates them'
        using errcode='42501';
    end if;
    v_target:=private.ensure_personal_space(v_me);
  else
    select s.personal_owner is not null into v_personal_target
    from public.spaces s where s.id=new.space_id;
    if coalesce(v_personal_target,false) then
      v_couple:=private.couple_space_id(v_me);
      if v_couple is null then
        new.visibility:='private';
        v_target:=new.space_id;
      else
        v_target:=v_couple;
      end if;
    else
      v_target:=new.space_id;
    end if;
  end if;

  if v_target is distinct from new.space_id then
    new.space_id:=v_target;
    if tg_table_name='activities' then
      if new.for_user_id is not null
         and not private.user_in_space(v_target,new.for_user_id) then
        new.for_user_id:=null;
      end if;
    elsif tg_table_name='shared_trips' then
      if new.traveler_id is not null
         and not private.user_in_space(v_target,new.traveler_id) then
        new.traveler_id:=null;
      end if;
    end if;
  end if;
  return new;
end
$function$
;
CREATE OR REPLACE FUNCTION private.activity_for_user_is_member()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if new.private_space_id is not null then
    if new.space_id is not null or new.created_by is distinct from new.private_space_id
      or new.visibility<>'private'
      or (new.for_user_id is not null and new.for_user_id<>new.created_by) then
      raise exception 'Personal Activity owner and assignee must be the same';
    end if;
    return new;
  end if;
  if new.for_user_id is not null
     and not private.user_in_space(new.space_id,new.for_user_id) then
    raise exception 'That person is not in this space';
  end if;
  return new;
end $function$
;
CREATE OR REPLACE FUNCTION private.audit_additional_record_action()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 kind text;
 before jsonb;
 after jsonb;
 fields text[];
 action_name text;
begin
 kind:=case tg_table_name
  when 'shared_trips' then 'trip'
  when 'saved_contacts' then 'contact'
  when 'daily_checkins' then 'checkin'
  when 'partner_checkin_requests' then 'checkin_request' when 'items_to_sort' then 'sort_item' when 'activities' then 'activity'
  else null end;
 if kind is null then raise exception 'Unsupported audited source';end if;
 after:=to_jsonb(new);
 if tg_op='INSERT' then
  action_name:='created';
  select coalesce(array_agg(key order by key),'{}'::text[]) into fields
  from jsonb_object_keys(after) as keys(key)
  where key not in ('updated_at','created_at','id','space_id','created_by');
 else
  before:=to_jsonb(old);
  select coalesce(array_agg(key order by key),'{}'::text[]) into fields
  from jsonb_object_keys(after) as keys(key)
  where (after->key) is distinct from (before->key)
   and key not in ('updated_at','created_at');
  if cardinality(fields)=0 then return new;end if;
  action_name:=case
   when before->>'archived_at' is null and
    after->>'archived_at' is not null then 'archived'
   when before->>'archived_at' is not null and
    after->>'archived_at' is null then 'restored'
   when kind='trip' and before->>'status'<>'cancelled'
    and after->>'status'='cancelled' then 'cancelled'
   when kind='trip' and before->>'status'='cancelled'
    and after->>'status'<>'cancelled' then 'reopened'
   when kind='activity' and (before->>'stage') is distinct from (after->>'stage') and (after->>'stage') in ('completed','purchased','registered') then 'completed' when kind='activity' and (before->>'stage') is distinct from (after->>'stage') and (after->>'stage')='cancelled' then 'cancelled' when (before->>'status') is distinct from (after->>'status') and (after->>'status') in ('completed','celebrated','enjoyed','booked') then 'completed' when (before->>'status') is distinct from (after->>'status') and (after->>'status')='cancelled' then 'cancelled' else 'edited' end;
 end if;
 insert into public.record_action_history(
  space_id,private_space_id,record_kind,record_id,actor_id,action,changed_fields)
 values((after->>'space_id')::uuid,(after->>'private_space_id')::uuid,
  kind,(after->>'id')::uuid,
  auth.uid(),action_name,fields);
 return new;
end;
$function$
;

-- Private root ownership is protected regardless of whether users use the UI.
do $guards$
declare tbl text; kind text;
begin
 for tbl,kind in select * from (values
   ('activities','activity'),('memories','memory')) x(tbl,kind)
 loop
   execute format('drop policy if exists "QA account owner selects private %s" on public.%I',tbl,tbl);
   execute format('create policy "QA account owner selects private %s" on public.%I for select to authenticated using (private_space_id=(select auth.uid()) and created_by=(select auth.uid()) and space_id is null and visibility=''private'')',tbl,tbl);
   execute format('drop policy if exists "QA account owner creates private %s" on public.%I',tbl,tbl);
   execute format('create policy "QA account owner creates private %s" on public.%I for insert to authenticated with check (private_space_id=(select auth.uid()) and created_by=(select auth.uid()) and space_id is null and visibility=''private'')',tbl,tbl);
   execute format('drop policy if exists "QA account owner updates private %s" on public.%I',tbl,tbl);
   execute format('create policy "QA account owner updates private %s" on public.%I for update to authenticated using (private_space_id=(select auth.uid()) and created_by=(select auth.uid()) and space_id is null and visibility=''private'') with check (private_space_id=(select auth.uid()) and created_by=(select auth.uid()) and space_id is null and visibility=''private'')',tbl,tbl);
   execute format('drop policy if exists "QA current pair creates shared %s" on public.%I',tbl,tbl);
   execute format('create policy "QA current pair creates shared %s" on public.%I as restrictive for insert to authenticated with check (visibility<>''shared'' or (select count(*) from public.space_members sm where sm.space_id=%I.space_id)=2)',tbl,tbl,tbl);
   execute format('drop policy if exists "QA current pair updates shared %s" on public.%I',tbl,tbl);
   execute format('create policy "QA current pair updates shared %s" on public.%I as restrictive for update to authenticated using (true) with check (visibility<>''shared'' or (select count(*) from public.space_members sm where sm.space_id=%I.space_id)=2)',tbl,tbl,tbl);
   execute format('drop trigger if exists qa_lock_personal_scope on public.%I',tbl);
   execute format('create trigger qa_lock_personal_scope before update on public.%I for each row execute function private.qa_lock_personal_root_scope()',tbl);
   execute format('drop policy if exists "QA owner reads private %s audit" on public.record_action_history',tbl);
   execute format('create policy "QA owner reads private %s audit" on public.record_action_history for select to authenticated using(record_kind=%L and private_space_id=(select auth.uid()) and exists (select 1 from public.%I a where a.id=record_id and a.private_space_id=(select auth.uid()) and a.created_by=(select auth.uid()) and a.visibility=''private''))',tbl,kind,tbl);
 end loop;
end $guards$;

-- Personal Memory is journal metadata until secure personal Storage is ready.
-- Photos, audio, galleries, scrapbook collaboration and invitations must not
-- be silently written through couple-scoped buckets.
alter table public.memories drop constraint if exists qa_private_memories_story_only;
alter table public.memories add constraint qa_private_memories_story_only
 check(private_space_id is null or memory_type='story') not valid;

-- Existing child RLS inherits authenticated parent visibility via SELECT.
-- Enforce parent/child IDs and prevent private media/mentions/reference links.
create or replace function private.qa_personal_activity_child_guard()
returns trigger language plpgsql set search_path='' as $guard$
declare p record; v_activity uuid:=(to_jsonb(new)->>'activity_id')::uuid;
 v_person uuid:=auth.uid(); v_component uuid;
begin
 select a.private_space_id,a.created_by,a.visibility
  into p from public.activities a where a.id=v_activity;
 if not found or p.private_space_id is null then return new; end if;
 if v_person is null or p.private_space_id<>v_person or p.created_by<>v_person then
   raise exception 'Personal Activity children belong only to its owner'
    using errcode='42501';
 end if;
 if tg_table_name='activity_components' then
   if new.created_by<>v_person or new.kind not in
      ('note','option','step','date','price','spec','reminder','tag','location','countdown') then
     raise exception 'This personal Activity component is not yet supported';
   end if;
   v_component:=new.parent_component_id;
 elsif tg_table_name='activity_comments' then
   if new.author_id<>v_person or new.voice_path is not null
     or new.voice_seconds is not null then
      raise exception 'Personal Activity voice storage is unavailable';
   end if;
   v_component:=new.component_id;
   if new.reply_to is not null and not exists(
      select 1 from public.activity_comments c where c.id=new.reply_to
       and c.activity_id=v_activity) then
       raise exception 'Reply must belong to the same Activity';
   end if;
 else return new;end if;
 if v_component is not null and not exists(
   select 1 from public.activity_components c
    where c.id=v_component and c.activity_id=v_activity) then
    raise exception 'Activity component must have the same parent';
 end if;
 return new;
end $guard$;
revoke all on function private.qa_personal_activity_child_guard()
 from public,anon,authenticated;
drop trigger if exists qa_personal_activity_components_guard on public.activity_components;
create trigger qa_personal_activity_components_guard
 before insert or update on public.activity_components for each row
 execute function private.qa_personal_activity_child_guard();
drop trigger if exists qa_personal_activity_comments_guard on public.activity_comments;
create trigger qa_personal_activity_comments_guard
 before insert on public.activity_comments for each row
 execute function private.qa_personal_activity_child_guard();

-- Block cross-scope photo/scrapbook writes until Storage is account-owned.
drop policy if exists "QA personal memories no couple-bucket photo writes" on public.memory_photos;
create policy "QA personal memories no couple-bucket photo writes" on public.memory_photos
 as restrictive for insert to authenticated with check (
   not exists(select 1 from public.memories m
     where m.id=memory_id and m.private_space_id is not null));
drop policy if exists "QA personal memories no couple-bucket photo updates" on public.memory_photos;
create policy "QA personal memories no couple-bucket photo updates" on public.memory_photos
 as restrictive for update to authenticated using(true)
 with check(not exists(select 1 from public.memories m
     where m.id=memory_id and m.private_space_id is not null));
drop policy if exists "QA personal memories no scrapbook page writes" on public.scrapbook_pages;
create policy "QA personal memories no scrapbook page writes" on public.scrapbook_pages
 as restrictive for insert to authenticated with check (
   not exists(select 1 from public.memories m
     where m.id=memory_id and m.private_space_id is not null));
drop policy if exists "QA personal memories no scrapbook page updates" on public.scrapbook_pages;
create policy "QA personal memories no scrapbook page updates" on public.scrapbook_pages
 as restrictive for update to authenticated using(true)
 with check(not exists(select 1 from public.memories m
     where m.id=memory_id and m.private_space_id is not null));

grant select,insert,update on public.activities,public.memories to authenticated;
