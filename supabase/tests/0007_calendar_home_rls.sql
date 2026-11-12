-- Runs inside a transaction and leaves no new records.
begin;
select set_config('qa.space',space_id::text,true)
  from public.space_members group by space_id having count(*)=2 limit 1;
select set_config('qa.a',user_id::text,true) from public.space_members
  where space_id=current_setting('qa.space')::uuid order by user_id limit 1;
select set_config('qa.b',user_id::text,true) from public.space_members
  where space_id=current_setting('qa.space')::uuid order by user_id desc limit 1;
set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('qa.a'),true);
do $$
declare v jsonb;
begin
 v:=public.get_home_snapshot();
 if v is null or (v->>'space_id')::uuid<>current_setting('qa.space')::uuid then
   raise exception 'Owner cannot load Home';
 end if;
 if (v->>'member_count')::int<>2 then raise exception 'Home membership missing'; end if;
 if not (v ? 'notes' and v ? 'calendar_entries' and v ? 'shopping_lists')
   then raise exception 'Home snapshot fields missing'; end if;
end $$;
insert into public.space_events(space_id,created_by,title,details,event_date,kind,recurrence,visibility)
values (current_setting('qa.space')::uuid,auth.uid(),'QA PRIVATE OCCASION','only creator',date '2026-12-14','occasion','yearly','private'),
(current_setting('qa.space')::uuid,auth.uid(),'QA SHARED EVENT','for both',date '2026-12-15','event','none','shared');
select set_config('qa.private',(select id::text from public.space_events where title='QA PRIVATE OCCASION'),true);
select set_config('request.jwt.claim.sub',current_setting('qa.b'),true);
do $$
declare denied boolean:=false;
begin
 if (select count(*) from public.space_events where title='QA PRIVATE OCCASION')<>0
   then raise exception 'Private event leaked'; end if;
 if (select count(*) from public.space_events where title='QA SHARED EVENT')<>1
   then raise exception 'Shared event not visible'; end if;
 begin
 perform public.set_object_share('event',current_setting('qa.private')::uuid,true);
 exception when others then denied:=true;
 end;
 if not denied then raise exception 'Partner can self-share private event'; end if;
end $$;
select set_config('request.jwt.claim.sub',current_setting('qa.a'),true);
select public.set_object_share('event',current_setting('qa.private')::uuid,true);
select set_config('request.jwt.claim.sub',current_setting('qa.b'),true);
do $$
begin
 if (select count(*) from public.space_events where id=current_setting('qa.private')::uuid)<>1 then raise exception 'Grant not visible'; end if;
 update public.space_events set title='ILLEGAL' where id=current_setting('qa.private')::uuid;
 if found then raise exception 'View-only recipient edited private event'; end if;
end $$;
select set_config('request.jwt.claim.sub',current_setting('qa.a'),true);
select public.set_object_share('event',current_setting('qa.private')::uuid,false);
select set_config('request.jwt.claim.sub',current_setting('qa.b'),true);
do $$
begin
 if (select count(*) from public.space_events where id=current_setting('qa.private')::uuid)<>0
 then raise exception 'Revoked event still readable'; end if;
 if public.get_home_snapshot() is null then raise exception 'Partner Home cannot load'; end if;
end $$;
select 'PASS home snapshot, event sharing, view-only and revocation' as result;
rollback;