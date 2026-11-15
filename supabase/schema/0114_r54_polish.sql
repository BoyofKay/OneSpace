-- OneSpace R54 - polish after R49-R53.
-- 1. Activities join the shared change log (record_kind 'activity'), so the
--    Activities screen gets the same clock/history page as every other list.
-- 2. Today's agenda gets "On this day": at most one past memory from today's
--    date (spec 3.5), read under the caller's own access rules.
-- Non-destructive: widened checks, one new policy, one new trigger, a
-- replaced read function.

alter table public.record_action_history drop constraint if exists record_action_history_record_kind_check,
 add constraint record_action_history_record_kind_check check (record_kind = any (array[
  'note','task','goal','memory','event','reminder','occasion','experience','trip','contact',
  'checkin','checkin_request','experience_comment','sort_item','activity']));

do $m$
declare d text:=pg_get_functiondef('private.audit_additional_record_action()'::regprocedure);
 o1 text:=$o$when 'items_to_sort' then 'sort_item'$o$;
 n1 text:=$n$when 'items_to_sort' then 'sort_item' when 'activities' then 'activity'$n$;
 o2 text:=$o$ when (before->>'status') is distinct from (after->>'status') and (after->>'status') in$o$;
 n2 text:=$n$ when kind='activity' and (before->>'stage') is distinct from (after->>'stage') and (after->>'stage') in ('completed','purchased','registered') then 'completed' when kind='activity' and (before->>'stage') is distinct from (after->>'stage') and (after->>'stage')='cancelled' then 'cancelled' when (before->>'status') is distinct from (after->>'status') and (after->>'status') in$n$;
begin
 if position('''activities'' then ''activity''' in d)>0 then return; end if;
 if position(o1 in d)=0 or position(o2 in d)=0 then raise exception 'pattern not found'; end if;
 execute replace(replace(d,o1,n1),o2,n2);
end $m$;
drop trigger if exists r54_activity_actions on public.activities;
create trigger r54_activity_actions after insert or update on public.activities
 for each row execute function private.audit_additional_record_action();

drop policy if exists "Read history of visible activities" on public.record_action_history;
create policy "Read history of visible activities" on public.record_action_history for select to authenticated
 using (record_kind = 'activity' and exists (select 1 from public.activities a
   where a.id = record_action_history.record_id and a.space_id = record_action_history.space_id));

do $m$
declare d text:=pg_get_functiondef('public.onespace_today(date)'::regprocedure);
 o text:=$o$   'active_trip',$o$;
 n text:=$n$   'on_this_day',(select jsonb_build_object('id',m.id,'title',m.title,
      'memory_date',m.memory_date,'years_ago',extract(year from p_today)::int-extract(year from m.memory_date)::int)
     from public.memories m
     where m.space_id=(snap->>'space_id')::uuid and m.archived_at is null
       and extract(month from m.memory_date)=extract(month from p_today)
       and extract(day from m.memory_date)=extract(day from p_today)
       and m.memory_date<p_today
     order by m.memory_date desc limit 1),
   'active_trip',$n$;
begin
 if position('on_this_day' in d)>0 then return; end if;
 if position(o in d)=0 then raise exception 'pattern not found'; end if;
 execute replace(d,o,n);
end $m$;
