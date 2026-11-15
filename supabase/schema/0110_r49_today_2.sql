-- OneSpace R49 - Today 2.0
-- Spec: UX Redesign Specification v1, section 3; backlog B-07..B-12 (partial, see docs/R49_TODAY_2_QA.md).
-- Non-destructive: one new read function, one new write function, one widened check.
--
-- onespace_today(p_today) is the single call Today makes (B-08). It keeps the
-- caller's own row-level security (SECURITY INVOKER), so nothing private to the
-- partner can leak, and returns:
--   snapshot     - get_home_snapshot_v2 (members, clocks, weather, counts, relationship)
--   attention    - onespace_my_attention (R47 rules)
--   coming_up    - onespace_coming_up (R47 rules)
--   since_away   - my unread notifications caused by my partner, newest first (max 5) + total
--   badges       - counts for shortcut tiles: unread letters, unread notifications
--   schedules    - each member's stated work/sleep hours, work days and time zone
--   active_trip  - a shared trip happening today, if any (hero "travelling" line)

create or replace function public.onespace_today(p_today date)
returns jsonb language sql stable security invoker set search_path to '' as $$
 with me as (select auth.uid() as id),
 unread as (
   select n.* from public.space_notifications n, me
   where n.recipient_id=me.id and n.read_at is null and n.actor_id<>me.id
 )
 select case when snap is null then null else
  snap || jsonb_build_object(
   'attention', public.onespace_my_attention(p_today),
   'coming_up', public.onespace_coming_up(p_today),
   'since_away', jsonb_build_object(
     'total',(select count(*) from unread),
     'items',(select coalesce(jsonb_agg(jsonb_build_object(
        'id',u.id,'kind',u.kind,'object_kind',u.object_kind,'object_id',u.object_id,
        'activity_id',u.activity_id,'calendar_event_id',u.calendar_event_id,
        'experience_id',u.experience_id,'trip_id',u.trip_id,'occasion_id',u.occasion_id,
        'memory_id',u.memory_id,'space_id',u.space_id,'action',u.action,
        'title',coalesce(u.push_title,u.headline),'body',u.push_body,
        'batch_count',u.batch_count,'created_at',u.created_at) order by u.created_at desc),'[]'::jsonb)
      from (select * from unread order by created_at desc limit 5) u)),
   'badges', jsonb_build_object(
     'letters',(select count(*) from unread where kind='letter'),
     'notifications',(select count(*) from unread)),
   'schedules',(select coalesce(jsonb_agg(jsonb_build_object(
      'user_id',p.id,'is_me',p.id=(select id from me),'time_zone',p.time_zone,
      'work_start',p.work_start_local,'work_end',p.work_end_local,
      'sleep_start',p.sleep_start_local,'sleep_end',p.sleep_end_local,
      'work_days',to_jsonb(p.work_days))),'[]'::jsonb)
     from public.space_members m join public.profiles p on p.id=m.user_id
     where m.space_id=(snap->>'space_id')::uuid),
   'active_trip',(select jsonb_build_object('id',t.id,'title',t.title,
      'destination',t.destination,'start_on',t.start_on,'end_on',t.end_on,'status',t.status)
     from public.shared_trips t
     where t.space_id=(snap->>'space_id')::uuid and t.archived_at is null
       and t.visibility='shared' and t.status not in ('cancelled','completed')
       and (t.status='traveling' or (t.start_on is not null and p_today between t.start_on and coalesce(t.end_on,t.start_on)))
     order by t.start_on nulls last limit 1)
  ) end
 from (select public.get_home_snapshot_v2(p_today) as snap) s
$$;
revoke all on function public.onespace_today(date) from public, anon;
grant execute on function public.onespace_today(date) to authenticated;

-- "How we live" from the hero, with a push to the partner (B-09).
alter table public.space_notifications
  drop constraint if exists space_notifications_object_kind_check,
  add constraint space_notifications_object_kind_check check (object_kind = any (array[
    'activity','letter','calendar','gesture','note','checkin','checkin_request',
    'experience','trip','occasion','task','reminder','scrapbook','memory','space']));

create or replace function public.set_how_we_live(p_together boolean)
returns text language plpgsql security definer set search_path to '' as $$
declare v_space uuid; v_old text; v_new text; v_peer uuid; v_zones int;
begin
 select m.space_id into v_space from public.space_members m where m.user_id=auth.uid() limit 1;
 if v_space is null then raise exception 'No shared space'; end if;
 select relationship_mode into v_old from public.spaces where id=v_space;
 if p_together then v_new:='living_together';
 else
   select count(distinct coalesce(nullif(p.time_zone,''),'UTC')) into v_zones
   from public.space_members m join public.profiles p on p.id=m.user_id where m.space_id=v_space;
   v_new:=case when coalesce(v_zones,1)>1 then 'apart_different_tz' else 'apart_same_tz' end;
 end if;
 if v_old is not distinct from v_new then return v_new; end if;
 update public.spaces set relationship_mode=v_new where id=v_space;
 for v_peer in select user_id from public.space_members where space_id=v_space and user_id<>auth.uid() loop
   perform private.post_notice(v_space,v_peer,auth.uid(),'change','space',v_space,
     'how we live',null,case when p_together then 'Now: Together' else 'Now: Apart' end,
     interval '2 minutes');
 end loop;
 return v_new;
end $$;
revoke all on function public.set_how_we_live(boolean) from public, anon;
grant execute on function public.set_how_we_live(boolean) to authenticated;
