-- QA: verify personal calendar events, event history and current pair
-- shared visibility. Changes are always rolled back.
begin;
select set_config('qa.owner',(select sm.user_id::text from public.space_members sm
 order by sm.space_id,sm.user_id limit 1),true);
select set_config('qa.space',(select sm.space_id::text from public.space_members sm
 where sm.user_id::text=current_setting('qa.owner') limit 1),true);
select set_config('qa.partner',(select sm.user_id::text from public.space_members sm
 where sm.space_id::text=current_setting('qa.space') and
 sm.user_id::text<>current_setting('qa.owner') limit 1),true);
select set_config('qa.stranger',(select sm.user_id::text from public.space_members sm
 where sm.space_id::text<>current_setting('qa.space') order by sm.user_id limit 1),true);
select set_config('request.jwt.claim.sub',current_setting('qa.owner'),true);
set local role authenticated;
do $checks$
declare o uuid:=current_setting('qa.owner')::uuid;
 peer uuid:=current_setting('qa.partner')::uuid;
 stranger uuid:=current_setting('qa.stranger')::uuid;
 sid uuid:=current_setting('qa.space')::uuid;
 personal uuid; couple uuid;n integer;
begin
 if o is null or peer is null or stranger is null then
  raise exception 'Need a pair and outside user for Calendar test';end if;
 insert into public.space_events(private_space_id,created_by,visibility,
 event_date,title,for_user_id,kind)
 values(o,o,'private',current_date,'QA isolated personal event',o,'event')
 returning id into personal;
 insert into public.space_events(space_id,created_by,visibility,
 event_date,title,for_user_id,kind)
 values(sid,o,'shared',current_date,'QA isolated couple event',peer,'event')
 returning id into couple;
 select count(*) into n from public.record_action_history h
 where h.record_id=personal and h.private_space_id=o and h.record_kind='event';
 if n<>1 then raise exception 'Private event audit missing';end if;
 perform set_config('request.jwt.claim.sub',peer::text,true);
 select count(*) into n from public.space_events e where e.id=personal;
 if n<>0 then raise exception 'Partner sees private event';end if;
 select count(*) into n from public.space_events e where e.id=couple;
 if n<>1 then raise exception 'Partner cannot read shared event';end if;
 perform set_config('request.jwt.claim.sub',stranger::text,true);
 select count(*) into n from public.space_events e where e.id=couple;
 if n<>0 then raise exception 'Outsider sees shared event';end if;
 select count(*) into n from public.record_action_history h where h.record_id=personal;
 if n<>0 then raise exception 'Outsider sees personal event history';end if;
 perform set_config('request.jwt.claim.sub',o::text,true);
 begin
  update public.space_events set created_by=peer where id=personal;
  raise exception 'BUG: personal event ownership could be changed';
 exception when others then
  if sqlerrm='BUG: personal event ownership could be changed' then raise;end if;
 end;
 update public.space_events set title='QA event changed by owner' where id=personal;
 select count(*) into n from public.space_events e where e.id=personal
 and e.title='QA event changed by owner';
 if n<>1 then raise exception 'Owner cannot edit personal event';end if;
end $checks$;
rollback;
