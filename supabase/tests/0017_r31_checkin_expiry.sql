-- R31 rollback-only lifecycle test; no lasting notifications or records.
begin;
select set_config('qa.space',space_id::text,true)
 from public.space_members group by space_id having count(*)=2 limit 1;
select set_config('qa.a',user_id::text,true)
 from public.space_members where space_id=current_setting('qa.space')::uuid
 order by joined_at limit 1;
select set_config('qa.b',user_id::text,true)
 from public.space_members where space_id=current_setting('qa.space')::uuid
 order by joined_at desc limit 1;

-- Deliberately construct historic records as postgres for test coverage;
-- app accounts cannot spoof their requested_at or expiry timestamp.
insert into public.partner_checkin_requests(
 space_id,sender_id,recipient_id,note,requested_at,expires_at)
 values(current_setting('qa.space')::uuid,current_setting('qa.a')::uuid,
 current_setting('qa.b')::uuid,'R31 expired QA',
 now()-interval '9 days',now()-interval '2 days'),
 (current_setting('qa.space')::uuid,current_setting('qa.a')::uuid,
 current_setting('qa.b')::uuid,'R31 legacy no-expiry QA',
 now()-interval '9 days',null);
select set_config('qa.expired',(select id::text from public.partner_checkin_requests
 where note='R31 expired QA' limit 1),true);
select set_config('qa.legacy',(select id::text from public.partner_checkin_requests
 where note='R31 legacy no-expiry QA' limit 1),true);

set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('qa.a'),true);
insert into public.partner_checkin_requests(space_id,sender_id,recipient_id,note)
 values(current_setting('qa.space')::uuid,current_setting('qa.a')::uuid,
 current_setting('qa.b')::uuid,'R31 fresh default QA');
select set_config('qa.fresh',(select id::text from public.partner_checkin_requests
 where note='R31 fresh default QA' limit 1),true);
do $qa$
declare expiry timestamptz;
begin
 select expires_at into expiry from public.partner_checkin_requests
 where id=current_setting('qa.fresh')::uuid;
 if expiry is null or expiry<now()+interval '6 days'
  or expiry>now()+interval '8 days' then
  raise exception 'Fresh request missing the expected expiry';
 end if;
end $qa$;

select set_config('request.jwt.claim.sub',current_setting('qa.b'),true);
do $qa$
declare blocked boolean:=false; modified integer;
begin
 begin
  update public.partner_checkin_requests set response_mood=3
   where id=current_setting('qa.expired')::uuid;
 exception when others then blocked:=true;end;
 if not blocked then raise exception 'Expired check-in was answerable';end if;
 update public.partner_checkin_requests set response_mood=4
  where id=current_setting('qa.fresh')::uuid;
 get diagnostics modified=row_count;
 if modified<>1 then raise exception 'Valid request cannot be answered';end if;
 begin
  update public.partner_checkin_requests set response_mood=5
   where id=current_setting('qa.fresh')::uuid;
 exception when others then blocked:=true;end;
 if (select responded_at from public.partner_checkin_requests
  where id=current_setting('qa.fresh')::uuid) is null then
  raise exception 'Fresh response missing server timestamp';end if;
 update public.partner_checkin_requests set response_mood=2
  where id=current_setting('qa.legacy')::uuid;
 get diagnostics modified=row_count;
 if modified<>1 then raise exception 'Legacy pending request was broken';end if;
end $qa$;
select 'PASS: R31 new seven-day expiry, old request compatibility and server reply guards' result;
rollback;