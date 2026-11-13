-- Deployed 20261113122732 onespace_r11_personal_actionable_attention
-- R11: actionable per-person attention. Privacy remains governed by source-table RLS.
create table public.user_attention_snoozes (
 user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
 source text not null check(source in ('activity','task','checkin')),
 object_id uuid not null,
 snoozed_until date not null check(snoozed_until between date '2000-01-01' and date '2100-12-31'),
 updated_at timestamptz not null default now(),
 primary key(user_id,source,object_id)
);
alter table public.user_attention_snoozes enable row level security;
create policy "Read my own attention snoozes"
 on public.user_attention_snoozes for select to authenticated
 using(user_id=(select auth.uid()));
create policy "Snooze only an object I can access"
 on public.user_attention_snoozes for insert to authenticated
 with check(user_id=(select auth.uid()) and (
   (source='activity' and exists(
     select 1 from public.activities a where a.id=object_id))
   or (source='task' and exists(
     select 1 from public.tasks t where t.id=object_id))
   or (source='checkin' and exists(
     select 1 from public.partner_checkin_requests r
     where r.id=object_id and r.recipient_id=(select auth.uid())))
 ));
create policy "Update only my own attention snoozes"
 on public.user_attention_snoozes for update to authenticated
 using(user_id=(select auth.uid()))
 with check(user_id=(select auth.uid()));
revoke all on public.user_attention_snoozes from public,anon,authenticated;
grant select on public.user_attention_snoozes to authenticated;
grant insert(user_id,source,object_id,snoozed_until) on public.user_attention_snoozes to authenticated;
grant update(snoozed_until) on public.user_attention_snoozes to authenticated;

create or replace function public.onespace_my_attention(p_today date)
returns jsonb language sql stable security invoker set search_path='' as $$
 with me as (select auth.uid() as id),
 my_space as (
   select space_id from public.space_members m,me
   where m.user_id=me.id
 ),
 candidates as (
   select 'activity'::text as source,a.id as object_id,a.id as activity_id,
     a.title,'activity'::text as kind,a.due_on,a.priority,
     case when a.due_on<p_today then 'Overdue activity'
       when a.due_on=p_today then 'Activity due today'
       when a.due_on=p_today+1 then 'Activity due tomorrow'
       when a.priority='urgent' then 'Urgent activity'
       else 'High-priority activity approaching' end as reason,
     case when a.due_on<p_today then 0
       when a.due_on=p_today then 1
       when a.due_on=p_today+1 then 3
       when a.priority='urgent' then 4 else 5 end as score
   from public.activities a join my_space m on m.space_id=a.space_id
   where a.archived_at is null and a.stage not in ('completed','cancelled')
     and (a.due_on<=p_today+1
       or (a.priority='high' and a.due_on between p_today+2 and p_today+3)
       or (a.priority='urgent' and a.due_on is null))
     and not exists (select 1 from public.activity_attention_snoozes s
       where s.activity_id=a.id and s.component_id is null
         and s.user_id=(select id from me) and s.snoozed_until>=p_today)
   union all
   select 'activity',a.id,a.id,
     coalesce(nullif(c.label,''),a.title),'reminder',
     v.due_on,a.priority,
     case when v.due_on<p_today then 'Overdue reminder'
       when v.due_on=p_today then 'Reminder due today'
       else 'Reminder due tomorrow' end,
     case when v.due_on<p_today then 0 when v.due_on=p_today then 1 else 3 end
   from public.activity_components c
   join public.activities a on a.id=c.activity_id
   join my_space m on m.space_id=a.space_id
   cross join lateral (select case
     when pg_catalog.pg_input_is_valid(c.payload->>'value','date')
       then (c.payload->>'value')::date end as due_on) v
   where a.archived_at is null and c.archived_at is null
     and a.stage not in ('completed','cancelled') and c.kind='reminder'
     and coalesce(c.payload->>'status','open')<>'done'
     and v.due_on<=p_today+1
     and not exists(select 1 from public.activity_attention_snoozes s
       where s.activity_id=a.id and s.user_id=(select id from me)
         and s.snoozed_until>=p_today
         and (s.component_id is null or s.component_id=c.id))
   union all
   select 'task',t.id,null::uuid,t.title,'task',t.target_date,t.priority,
     case when t.target_date<p_today then 'Overdue to-do'
       when t.target_date=p_today then 'To-do due today'
       when t.target_date=p_today+1 then 'To-do due tomorrow'
       when t.priority='urgent' then 'Urgent to-do'
       else 'High-priority to-do approaching' end,
     case when t.target_date<p_today then 0
       when t.target_date=p_today then 1
       when t.target_date=p_today+1 then 3
       when t.priority='urgent' then 4 else 5 end
   from public.tasks t join my_space m on m.space_id=t.space_id,me
   where t.status='open'
     and (t.assigned_to=me.id or
       (t.assigned_to is null and (t.created_by=me.id or t.visibility='shared')))
     and (t.target_date<=p_today+1
       or (t.priority='high' and t.target_date between p_today+2 and p_today+3)
       or (t.priority='urgent' and t.target_date is null))
   union all
   select 'checkin',r.id,null::uuid,
     'Your partner asked how you are feeling','checkin',
     null::date,'normal','Respond to a partner check-in',2
   from public.partner_checkin_requests r
   join my_space m on m.space_id=r.space_id,me
   where r.recipient_id=me.id and r.responded_at is null
   union all
   select 'activity',a.id,a.id,a.title,'mention',
     null::date,'normal',
     case when n.kind='mention' then 'Your partner mentioned you'
       else 'Unread Activity reply' end,2
   from public.space_notifications n
   join public.activities a on a.id=n.activity_id
   join my_space m on m.space_id=n.space_id,me
   where n.recipient_id=me.id and n.read_at is null
     and n.kind in ('mention','reply') and n.object_kind='activity'
     and a.archived_at is null
 ),
 filtered as (
   select c.* from candidates c
   left join public.user_attention_snoozes us
     on us.user_id=(select id from me)
       and us.source=c.source and us.object_id=c.object_id
       and us.snoozed_until>=p_today
   where us.object_id is null
 ),
 grouped as (
   select distinct on(source,object_id)
     source,object_id,activity_id,title,kind,due_on,priority,reason,score
   from filtered
   order by source,object_id,score,due_on nulls last,title
 ),
 nearest as(
   select * from grouped order by score,due_on nulls last,title limit 20
 )
 select coalesce(jsonb_agg(jsonb_build_object(
   'id',object_id,'source',source,'activity_id',activity_id,
   'title',title,'kind',kind,'due_on',due_on,
   'priority',priority,'reason',reason,'score',score)
   order by score,due_on nulls last,title),'[]'::jsonb)
 from nearest;
$$;
revoke all on function public.onespace_my_attention(date) from public,anon;
grant execute on function public.onespace_my_attention(date) to authenticated;
