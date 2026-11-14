-- R44: permissioned audit history, no test data persists.
begin;
select set_config('qa.space',space_id::text,true)
 from public.space_members group by space_id having count(*)=2 limit 1;
select set_config('qa.a',user_id::text,true)
 from public.space_members where space_id=current_setting('qa.space')::uuid
 order by joined_at limit 1;
select set_config('qa.b',user_id::text,true)
 from public.space_members where space_id=current_setting('qa.space')::uuid
 order by joined_at desc limit 1;
set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('qa.a'),true);
insert into public.shared_trips(space_id,created_by,title,visibility)
 values(current_setting('qa.space')::uuid,current_setting('qa.a')::uuid,
 'R44 shared trip audit QA','shared');
insert into public.saved_contacts(space_id,created_by,visibility,label,payload)
 values(current_setting('qa.space')::uuid,current_setting('qa.a')::uuid,
 'private','R44 private contact audit QA','{}'::jsonb);
insert into public.daily_checkins(space_id,created_by,
 checkin_date,mood,message,gratitude,visibility)
 values(current_setting('qa.space')::uuid,current_setting('qa.a')::uuid,
 date '1901-04-26',3,'R44 private check-in sample',
 'R44 sample gratitude','private');
insert into public.partner_checkin_requests(space_id,sender_id,recipient_id,note)
 values(current_setting('qa.space')::uuid,current_setting('qa.a')::uuid,
 current_setting('qa.b')::uuid,'R44 sent request audit QA');
select set_config('qa.trip',(select id::text from public.shared_trips
 where title='R44 shared trip audit QA' limit 1),true);
select set_config('qa.contact',(select id::text from public.saved_contacts
 where label='R44 private contact audit QA' limit 1),true);
select set_config('qa.checkin',(select id::text from public.daily_checkins
 where checkin_date=date '1901-04-26' and created_by=current_setting('qa.a')::uuid
 limit 1),true);
select set_config('qa.request',(select id::text from public.partner_checkin_requests
 where note='R44 sent request audit QA' limit 1),true);
update public.shared_trips set status='cancelled'
 where id=current_setting('qa.trip')::uuid;
update public.saved_contacts set archived_at=now()
 where id=current_setting('qa.contact')::uuid;
update public.saved_contacts set archived_at=null
 where id=current_setting('qa.contact')::uuid;
update public.daily_checkins set gratitude='Updated only in private check-in'
 where id=current_setting('qa.checkin')::uuid;
do $qa$
declare kinds int; trip_actions int; contact_actions int;
begin
 select count(distinct record_kind) into kinds from public.record_action_history
 where record_id in (current_setting('qa.trip')::uuid,
 current_setting('qa.contact')::uuid,current_setting('qa.checkin')::uuid,
 current_setting('qa.request')::uuid);
 if kinds<>4 then raise exception 'Expected four audited record kinds, found %',kinds;end if;
 select count(*) into trip_actions from public.record_action_history
 where record_id=current_setting('qa.trip')::uuid and action='cancelled'
 and 'status'=any(changed_fields) and actor_id=current_setting('qa.a')::uuid;
 if trip_actions<>1 then raise exception 'Cancelled trip audit event missing';end if;
 select count(*) into contact_actions from public.record_action_history
 where record_id=current_setting('qa.contact')::uuid and action in ('archived','restored');
 if contact_actions<>2 then raise exception 'Contact archive/restore history missing';end if;
 if not exists(select 1 from public.record_action_history where
  record_id=current_setting('qa.checkin')::uuid and
  action='edited' and 'gratitude'=any(changed_fields)) then
  raise exception 'Private check-in field-change audit missing';end if;
 if exists(select 1 from public.record_action_history where
  record_id=current_setting('qa.checkin')::uuid and
  'Updated only in private check-in'=any(changed_fields)) then
  raise exception 'Sensitive content leaked to audit log';end if;
end $qa$;
select set_config('request.jwt.claim.sub',current_setting('qa.b'),true);
do $qa$
begin
 if not exists(select 1 from public.record_action_history
  where record_id=current_setting('qa.trip')::uuid and action='created')then
   raise exception 'Shared trip history missing for partner';end if;
 if exists(select 1 from public.record_action_history
  where record_id in (current_setting('qa.contact')::uuid,
  current_setting('qa.checkin')::uuid))then
   raise exception 'Private contact/check-in history leaked to partner';end if;
end $qa$;
select 'PASS: R44 actor/fields/time and shared vs private RLS, no data content copied' result;
rollback;